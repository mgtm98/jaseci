import time;
import from jaclang.compiler.frontend.srcloc { CodeLocInfo, Span }
import from jaclang.compiler.frontend.diagnostics {
    DiagnosticInfo,
    E9001,
    LINT_ALIASES,
    Severity
}
import from jaclang.compiler.frontend.diagnostic_utils { resolve_diagnostic_tokens }
import from abc { ABC }
import from jaclang.compiler.frontend.unitree { UniNode }

# JAC_PROFILE_PASSES mode, read once per process (empty string = disabled).
glob _PASS_PROFILE_MODE: list[str] = [];

obj Alert {
    has msg: str,
        loc: Span,
        from_pass: type[Transform],
        code: DiagnosticInfo | None = None,
        related: list[tuple[str, Span]] = [],
        help_text: str | None = None,
        owner: str = '';

    def postinit -> None;
    def __str__ -> str;
    def __repr__ -> str;
    def as_log(*, colors: bool = False) -> str;
    def pretty_print(*, colors: bool = False) -> str;
}

obj DiagnosticPolicy {
    has suppress_codes: list[str] = [],
        suppress_categories: list[str] = [],
        lint_active: bool = False,
        lint_select: list[str] = [],
        lint_ignore: list[str] = [],
        _inline_cache: dict[(tuple[str, int], list[str])] = {};

    def is_suppressed(
        diag: DiagnosticInfo, loc: (CodeLocInfo | Span | None) = None
    ) -> bool;

    def _inline_suppressed(diag: DiagnosticInfo, loc: (CodeLocInfo | Span)) -> bool;
}

obj BaseTransform(ABC) {
    has ir_in: UniNode,
        cancel_token: any = None,
        cancel_requested: bool = False,
        errors_had: list[Alert] = [],
        warnings_had: list[Alert] = [],
        time_taken: float = 0.0,
        ir_out: UniNode postinit;

    def postinit -> None;
    def timed_transform(ir_in: UniNode) -> UniNode {
        # Opt-in per-pass profiling: JAC_PROFILE_PASSES=1 prints each pass's
        # wall time, process RSS high-water mark, and RSS delta to stderr;
        # JAC_PROFILE_PASSES=peak additionally tracks the Python-heap peak
        # allocated during the pass (tracemalloc; ~2x slower). Unset -> the
        # plain time-only path below, unchanged.
        if not _PASS_PROFILE_MODE {
            import os;
            _PASS_PROFILE_MODE.append(
                os.environ.get("JAC_PROFILE_PASSES", "").strip().lower()
            );
        }
        if not _PASS_PROFILE_MODE[0] {
            start_time = time.time();
            ir_out = self.transform(ir_in=ir_in);
            self.time_taken = time.time() - start_time;
            return ir_out;
        }
        import sys;
        import resource;
        _pp_peak = _PASS_PROFILE_MODE[0] == "peak";
        _pp_started_trace = False;
        _pp_py_before = 0;
        if _pp_peak {
            import tracemalloc;
            if not tracemalloc.is_tracing() {
                tracemalloc.start();
                _pp_started_trace = True;
            }
            (_pp_py_before, _) = tracemalloc.get_traced_memory();
        }
        _pp_rss_before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss;
        start_time = time.time();
        ir_out = self.transform(ir_in=ir_in);
        self.time_taken = time.time() - start_time;
        _pp_rss_after = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss;
        # ru_maxrss is KiB on Linux and a high-water mark: the delta can only
        # show growth, never shrinkage.
        _pp_line = (
            f"[PASS-PROFILE] {self.__class__.__name__}  "
            + f"time={self.time_taken * 1000.0:.1f}ms "
            + f"rss_hwm={_pp_rss_after / 1024.0:.1f}MiB "
            + f"(+{(_pp_rss_after - _pp_rss_before) / 1024.0:.1f}MiB)"
        );
        if _pp_peak {
            import tracemalloc;
            (_, _pp_py_peak) = tracemalloc.get_traced_memory();
            _pp_delta = _pp_py_peak - _pp_py_before;
            if _pp_delta < 0 {
                _pp_delta = 0;
            }
            _pp_line = _pp_line + f" py_peak={_pp_delta / 1048576.0:.1f}MiB";
            if _pp_started_trace {
                tracemalloc.stop();
            }
        }
        _pp_mod = "";
        try {
            _pp_mod = ir_in.loc.mod_path or "";
        } except Exception {}
        if _pp_mod {
            _pp_line = _pp_line + f"  mod={_pp_mod}";
        }
        sys.stderr.write(_pp_line + "\n");
        sys.stderr.flush();
        return ir_out;
    }

    def pre_transform -> None;
    def post_transform -> None;
    def transform(ir_in: UniNode) -> UniNode {
        return ir_in;
    }

    def log_info(msg: str) -> None;
    def is_canceled -> bool;
}

obj Transform(BaseTransform) {
    has cur_node: UniNode postinit,
        policy: (DiagnosticPolicy | None) = None;

    static has PROVIDES: tuple = (),
        REQUIRES: tuple = (),
        HOST_PASS: bool = False;

    def postinit -> None;
    def emit(
        diag: DiagnosticInfo,
        node_override: (UniNode | None) = None,
        related: (list[tuple[str, UniNode]] | None) = None,
        help_text: (str | None) = None,
        **kwargs: any
    ) -> bool;

    def _is_suppressed(diag: DiagnosticInfo, loc: CodeLocInfo | None = None) -> bool;
    def ice(msg: str = 'Something went horribly wrong!') -> str;
}
