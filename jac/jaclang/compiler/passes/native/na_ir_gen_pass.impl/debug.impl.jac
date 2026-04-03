"""Debug helpers: post_transform dumps/validates the generated LLVM IR.

Environment variables
---------------------
JAC_DEBUG_IR=1        — save IR to .jac_ir/<stem>.ll next to the source file
JAC_VERIFY_IR=1       — run llvmlite parse_assembly to verify the IR
"""
import from jaclang.cli.console { console }
import from llvmlite { binding as llvm }
import os;
import sys;

"""Dump and/or validate the generated LLVM IR.  Called after transform()."""
impl NaIRGenPass.post_transform -> None {
    if not self.has_native_code {
        return;
    }

    # ── Emit DWARF compile-unit and required module flags (JAC_NATIVE_DEBUG) ──
    if self.di_cu is not None {
        try {
            self.llvm_module.add_named_metadata("llvm.dbg.cu").add(self.di_cu);
            _nm_flags = self.llvm_module.add_named_metadata("llvm.module.flags");
            _nm_flags.add(
                self.llvm_module.add_metadata(
                    [
                        ir.Constant(ir.IntType(32), 7),
                        "Dwarf Version",
                        ir.Constant(ir.IntType(32), 5)
                    ]
                )
            );
            _nm_flags.add(
                self.llvm_module.add_metadata(
                    [
                        ir.Constant(ir.IntType(32), 2),
                        "Debug Info Version",
                        ir.Constant(ir.IntType(32), 3)
                    ]
                )
            );
        } except Exception {
            pass;  # debug flags are best-effort
        }
    }

    ir_str = str(self.llvm_module);

    # ── Auto-save to .jac_ir/<stem>.ll when JAC_DEBUG_IR is set ─────────────
    if os.environ.get("JAC_DEBUG_IR", False) {
        src_path = self.ir_in.loc.mod_path;
        if src_path {
            src_dir = os.path.dirname(os.path.abspath(src_path));
            stem = os.path.splitext(os.path.basename(src_path))[0];
            ir_dir = os.path.join(src_dir, ".jac_ir");
            os.makedirs(ir_dir, exist_ok=True);
            auto_ir_path = os.path.join(ir_dir, stem + ".ll");
            with open(auto_ir_path, "w") as f {
                f.write(ir_str);
            }
            console.print(f"[JAC_DEBUG_IR] IR saved to: {auto_ir_path}");
        }
    }

    # ── Validate via parse_assembly ──────────────────────────────────────────
    if os.environ.get("JAC_VERIFY_IR", False) {
        console.print("[JAC_VERIFY_IR] Verifying LLVM IR ...");
        try {
            llvm.initialize();
            llvm.initialize_native_target();
            llvm.initialize_native_asmprinter();
            mod = llvm.parse_assembly(ir_str);
            mod.verify();
            console.print("[JAC_VERIFY_IR] OK — IR verified successfully.");
        } except Exception as exc {
            console.print(f"[JAC_VERIFY_IR] VERIFICATION FAILED: {exc}");
        }
    }
}
