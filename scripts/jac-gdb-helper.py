"""
jac-gdb-helper.py — GDB Python extension for Jac native debug support.

Loaded by `jac-gdb` via `source jac-gdb-helper.py`.  Provides:

  jac-load-symbols [path]   — Load debug symbols from a .symmap file produced
                               by the Jac native compiler (JAC_NATIVE_DEBUG=1).

The .symmap file contains:
  Line 1: path to the debug .o file (ELF with DWARF sections)
  Line 2: hex address of the .text region in JIT memory
  Lines 3+: <function_name> <hex_addr>  (per-function JIT addresses)
"""

import glob
import os

import gdb  # type: ignore


class JacLoadSymbols(gdb.Command):
    """Load Jac native debug symbols from a .symmap file.

    Usage: jac-load-symbols [/path/to/file.symmap]

    If no path is given, looks for $JAC_SYMMAP_PATH, then searches /tmp
    and the working directory for '*.symmap' files.
    """

    def __init__(self):
        super().__init__("jac-load-symbols", gdb.COMMAND_USER)

    def _find_symmap(self, arg: str) -> str:
        """Resolve the symmap path from argument, env var, or search."""
        if arg:
            return arg

        # Env var set by jac-gdb
        env_path = os.environ.get("JAC_SYMMAP_PATH", "")
        if env_path and os.path.isfile(env_path):
            return env_path

        # Search common locations
        candidates = glob.glob("/tmp/jac_debug*.symmap")
        candidates += glob.glob("**/.jac_ir/*.symmap", recursive=True)
        if candidates:
            # Use the most recently modified one
            candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            return candidates[0]

        return ""

    def invoke(self, arg: str, from_tty: bool) -> None:
        symmap_path = self._find_symmap(arg.strip())

        if not symmap_path or not os.path.isfile(symmap_path):
            gdb.write(
                "Error: no .symmap file found.\n"
                "  Ensure JAC_NATIVE_DEBUG=1 was set during compilation.\n"
                "  Usage: jac-load-symbols /path/to/file.symmap\n"
            )
            return

        try:
            with open(symmap_path) as f:
                lines = [ln.strip() for ln in f if ln.strip()]
        except Exception as e:
            gdb.write(f"Error reading {symmap_path}: {e}\n")
            return

        if len(lines) < 2:
            gdb.write(f"Error: malformed symmap (need >=2 lines): {symmap_path}\n")
            return

        obj_path = lines[0]
        text_addr = lines[1]

        # Parse per-function JIT addresses from symmap
        fn_jit_addrs = {}
        for line in lines[2:]:
            parts = line.split()
            if len(parts) == 2:
                fn_jit_addrs[parts[0]] = int(parts[1], 16)

        if not os.path.isfile(obj_path):
            gdb.write(f"Error: debug object not found: {obj_path}\n")
            return

        # Determine the correct code section name.  MCJIT's large code model
        # emits code into `.ltext` (not `.text`).  Also read function offsets
        # within that section so we can compute the true section base.
        code_section = ".text"
        fn_obj_offsets = {}
        try:
            import subprocess

            # Get section headers
            _readelf_s = subprocess.run(
                ["readelf", "-S", obj_path],
                capture_output=True,
                text=True,
            )
            if ".ltext" in _readelf_s.stdout:
                code_section = ".ltext"

            # Get symbol table to find function offsets within the section
            _readelf_sym = subprocess.run(
                ["readelf", "-s", obj_path],
                capture_output=True,
                text=True,
            )
            for line in _readelf_sym.stdout.splitlines():
                # Format: Num Value Size Type Bind Vis Ndx Name
                parts = line.split()
                if len(parts) >= 8 and parts[3] == "FUNC":
                    fname = parts[7]
                    foffset = int(parts[1], 16)
                    fn_obj_offsets[fname] = foffset
        except Exception:
            pass

        # Compute the true section base address.
        # In the object file, functions sit at known offsets within .ltext.
        # In JIT memory, MCJIT loads the whole section contiguously.
        # So: section_base = fn_jit_addr - fn_obj_offset
        section_base = int(text_addr, 16)
        for fname, jit_addr in fn_jit_addrs.items():
            if fname in fn_obj_offsets:
                computed_base = jit_addr - fn_obj_offsets[fname]
                section_base = computed_base
                break

        section_base_hex = f"0x{section_base:x}"

        gdb.write(f"Loading debug symbols from: {obj_path}\n")
        gdb.write(f"  {code_section} base: {section_base_hex}\n")

        # Suppress the "are you sure?" prompt
        try:
            gdb.execute("set confirm off")
            cmd = f"add-symbol-file {obj_path} -s {code_section} {section_base_hex}"
            gdb.execute(cmd, to_string=False)
            gdb.execute("set confirm on")
        except gdb.error as e:
            gdb.write(f"Warning: add-symbol-file failed: {e}\n")
            gdb.execute("set confirm on")
            return

        # Show per-function addresses
        if fn_jit_addrs:
            gdb.write("\nJIT function addresses:\n")
            for fname, jit_addr in fn_jit_addrs.items():
                gdb.write(f"  {fname:40s} 0x{jit_addr:x}\n")

        gdb.write("\nSymbols loaded. Use 'jac-bt' for a Jac-only backtrace.\n")


class JacAutoSymbols(gdb.Command):
    """Automatically search for and load Jac debug symbols after a crash.

    Usage: jac-auto-symbols
    """

    def __init__(self):
        super().__init__("jac-auto-symbols", gdb.COMMAND_USER)

    def invoke(self, arg: str, from_tty: bool) -> None:
        symmap_path = os.environ.get("JAC_SYMMAP_PATH", "")
        if symmap_path and os.path.isfile(symmap_path):
            gdb.execute(f"jac-load-symbols {symmap_path}")
        else:
            # Try to find it
            gdb.execute("jac-load-symbols")


class JacBacktrace(gdb.Command):
    """Show a Jac-only backtrace, starting from jac_entry down to the crash.

    Filters out Python, ctypes, ffi, and libc frames so only the
    native Jac call chain is visible.  Falls back to full `bt` if
    jac_entry is not found in the trace.

    Usage: jac-bt
    """

    def __init__(self):
        super().__init__("jac-bt", gdb.COMMAND_USER)

    def invoke(self, arg: str, from_tty: bool) -> None:
        # Collect all frames
        frame = gdb.newest_frame()
        frames = []
        while frame is not None:
            frames.append(frame)
            try:
                frame = frame.older()
            except gdb.error:
                break

        # Find jac_entry — everything from the crash (frame 0) up
        # to and including jac_entry is the Jac call chain.
        jac_entry_idx = None
        for i, f in enumerate(frames):
            name = f.name() or ""
            if name == "jac_entry":
                jac_entry_idx = i
                break

        if jac_entry_idx is None:
            gdb.write("jac_entry not found in trace — showing full bt:\n\n")
            gdb.execute("bt")
            return

        # Print frames 0 .. jac_entry_idx  (crash → jac_entry)
        gdb.write("Jac backtrace:\n")
        for i in range(jac_entry_idx + 1):
            f = frames[i]
            name = f.name() or "??"
            sal = f.find_sal()
            loc = ""
            if sal.symtab:
                loc = f" at {sal.symtab.filename}:{sal.line}"
            gdb.write(f"  #{i:<3d} 0x{f.pc():016x} in {name}(){loc}\n")
        gdb.write("\n")


# Register commands
JacLoadSymbols()
JacAutoSymbols()
JacBacktrace()

gdb.write(
    "[jac-gdb] Helper loaded. Commands: jac-bt, jac-load-symbols, jac-auto-symbols\n"
)
