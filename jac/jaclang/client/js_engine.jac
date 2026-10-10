import ctypes;
import os;
import signal;
import sys;
import tempfile;
import threading;
import from functools { cache }

import from jaclang.dist.fused_binary { interpreter_runtime_dir }

def engine_dir -> str {
    """The bundled JavaScript engine's directory in the runtime tree: its
    libraries, its builtins pack and `bin/node`.""";
    rt = interpreter_runtime_dir();
    if rt is None {
        raise RuntimeError(
            "the JavaScript engine ships inside the jac binary; run jac from it"
        );
    }
    return os.path.join(rt, "js");
}

def node_executable -> str {
    """This binary under the name `node`: running it runs the bundled engine
    (the launcher keeps the link pointing here).""";
    return os.path.join(engine_dir(), "bin", "node");
}

@cache
def _library -> ctypes.CDLL {
    lib = ctypes.CDLL(os.path.join(engine_dir(), "libjs_engine.so"));
    lib.js_pm.argtypes = [ctypes.c_int64, ctypes.POINTER(ctypes.c_char_p)];
    lib.js_pm.restype = ctypes.c_int64;
    return lib;
}

def run_pm(args: list[str], cwd: str, capture: bool = False) -> tuple[int, str] {
    """Run a package-manager command (`["install"]`, `["add", "-d", "vite"]`)
    in `cwd` inside this process and return its exit code, plus its output
    when `capture` is set (it otherwise streams to this process's stdout and
    stderr). The process's directory and umask are restored afterwards, and
    Ctrl+C stops the command the way it stops a standalone one.""";
    lib = _library();
    argv = (ctypes.c_char_p * (len(args) + 1))(b"node", *[a.encode() for a in args]);
    sys.stdout.flush();
    sys.stderr.flush();
    saved_cwd = os.getcwd();
    saved_umask = os.umask(0);
    os.umask(saved_umask);
    main_thread = threading.current_thread() is threading.main_thread();
    saved_sigint = signal.signal(signal.SIGINT, signal.SIG_DFL)
        if main_thread
        else None;
    out = tempfile.TemporaryFile() if capture else None;
    saved_fds: list[int] = [];
    try {
        if out is not None {
            saved_fds = [os.dup(1), os.dup(2)];
            os.dup2(out.fileno(), 1);
            os.dup2(out.fileno(), 2);
        }
        os.chdir(cwd);
        rc = int(lib.js_pm(len(args) + 1, argv));
    } finally {
        os.chdir(saved_cwd);
        os.umask(saved_umask);
        if saved_fds {
            os.dup2(saved_fds[0], 1);
            os.dup2(saved_fds[1], 2);
            for fd in saved_fds {
                os.close(fd);
            }
        }
        if saved_sigint is not None {
            signal.signal(signal.SIGINT, saved_sigint);
        }
    }
    if out is None {
        return (rc, "");
    }
    out.seek(0);
    text = out.read().decode("utf-8", "replace");
    out.close();
    return (rc, text);
}
