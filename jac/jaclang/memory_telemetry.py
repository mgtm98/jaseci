"""Memory telemetry for Jac runtime and compiler.

Enable detailed snapshots with ``JAC_MEM_DEBUG=1``.
Bytecode lifecycle counters support compile/import/unload regression tests.
"""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

_TRUTHY = frozenset({"1", "true", "yes", "on"})


def mem_debug_enabled() -> bool:
    return os.environ.get("JAC_MEM_DEBUG", "").strip().lower() in _TRUTHY


def mem_strict_invariants_enabled() -> bool:
    """When true, unload/invalidate paths may assert registry consistency."""
    return os.environ.get("JAC_MEM_STRICT", "").strip().lower() in _TRUTHY


def module_eviction_enabled() -> bool:
    """When true, optional dynamic-module LRU eviction may run."""
    val = os.environ.get("JAC_ENABLE_MODULE_EVICTION", "1").strip().lower()
    return val in _TRUTHY


def dynamic_module_limit() -> int | None:
    """Max retained dynamic modules when eviction is enabled; None = unlimited."""
    raw = os.environ.get("JAC_DYNAMIC_MODULE_LIMIT", "").strip()
    if not raw:
        return None
    try:
        return max(0, int(raw))
    except ValueError:
        return None


def hub_cache_limit() -> int | None:
    """Max hub entries per JacProgram when bounded retention is enabled."""
    raw = os.environ.get("JAC_HUB_CACHE_LIMIT", "").strip()
    if not raw:
        return None
    try:
        return max(1, int(raw))
    except ValueError:
        return None


def hub_cache_bounding_enabled() -> bool:
    val = os.environ.get("JAC_ENABLE_HUB_CACHE_BOUND", "1").strip().lower()
    return val in _TRUTHY


def _memory_stats(mem: Any) -> dict[str, Any]:
    if mem is None:
        return {}
    stats_fn = getattr(mem, "memory_stats", None)
    if callable(stats_fn):
        return dict(stats_fn())
    get_mem = getattr(mem, "get_mem", None)
    get_gc = getattr(mem, "get_gc", None)
    out: dict[str, Any] = {"type": type(mem).__name__}
    if callable(get_mem):
        out["l1_count"] = len(get_mem())
    if callable(get_gc):
        out["gc_queue_count"] = len(get_gc())
    return out


def _hub_bytecode_bytes_estimate(program: Any) -> int:
    hub = getattr(getattr(program, "mod", None), "hub", None) or {}
    total = 0
    for mod in hub.values():
        gen = getattr(mod, "gen", None)
        if gen is None:
            continue
        bc = getattr(gen, "py_bytecode", None)
        if isinstance(bc, (bytes, bytearray)):
            total += len(bc)
    return total


def program_memory_snapshot(program: Any) -> dict[str, Any]:
    hub = getattr(getattr(program, "mod", None), "hub", None) or {}
    snap: dict[str, Any] = {
        "hub_modules": len(hub),
        "hub_bytecode_bytes": _hub_bytecode_bytes_estimate(program),
        "mtir_map": len(getattr(program, "mtir_map", {}) or {}),
        "mtir_scope_modules": len(getattr(program, "_mtir_scope_modules", {}) or {}),
        "errors_had": len(getattr(program, "errors_had", []) or []),
        "warnings_had": len(getattr(program, "warnings_had", []) or []),
        "native_cache": len(getattr(program, "_native_cache", {}) or {}),
        "hub_cache_times": len(getattr(program, "_hub_cache_times", {}) or {}),
        "dependents": len(getattr(program, "_dependents", {}) or {}),
        "mtir_scopes_by_module": len(
            getattr(program, "_mtir_scopes_by_module", {}) or {}
        ),
    }
    te = getattr(program, "type_evaluator", None)
    if te is not None and hasattr(te, "memory_stats"):
        snap["type_evaluator"] = te.memory_stats()
    return snap


def runtime_module_registry_snapshot() -> dict[str, Any]:
    from jaclang.jac0core.runtime import JacRuntime

    paths = getattr(JacRuntime, "module_resolved_paths", None) or {}
    names_by_path = getattr(JacRuntime, "resolved_path_module_names", None) or {}
    aliases = getattr(JacRuntime, "dynamic_module_aliases", None) or {}
    return {
        "module_resolved_paths": len(paths),
        "resolved_path_module_names": len(names_by_path),
        "dynamic_module_aliases": len(aliases),
    }


def runtime_memory_snapshot() -> dict[str, Any]:
    from jaclang.jac0core.runtime import JacRuntime

    loaded = JacRuntime.loaded_modules
    dynamic = [
        n
        for n in loaded
        if n.startswith("_dynamic_module_")
        or n.startswith("_dyn_")
        or "_dynamic" in n
    ]
    snap: dict[str, Any] = {
        "loaded_modules": len(loaded),
        "dynamic_modules": len(dynamic),
        "module_registry": runtime_module_registry_snapshot(),
    }
    if JacRuntime.exec_ctx is not None:
        snap["execution_context"] = _memory_stats(JacRuntime.exec_ctx.mem)
    if JacRuntime.program is not None:
        snap["program"] = program_memory_snapshot(JacRuntime.program)
    return snap


def memory_snapshot() -> dict[str, Any]:
    return {
        "runtime": runtime_memory_snapshot(),
    }


def log_memory_snapshot(label: str = "jac_mem") -> dict[str, Any]:
    snap = memory_snapshot()
    if mem_debug_enabled():
        logger.info("%s snapshot: %s", label, snap)
    return snap


def assert_no_orphaned_module_paths(
    *,
    resolved_path: str,
    program: Any | None,
) -> None:
    """Debug-only: paths should not remain in hub after coordinated unload."""
    if not mem_strict_invariants_enabled() or program is None:
        return
    hub = getattr(getattr(program, "mod", None), "hub", None) or {}
    if resolved_path in hub:
        raise AssertionError(
            f"orphaned hub entry after unload: {resolved_path}"
        )
