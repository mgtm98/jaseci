"""Memory retention regression tests for runtime and compiler caches."""

import from typing { cast }
import from jaclang.jac0core.archetype { NodeAnchor, Root }
import from jaclang.jac0core.runtime { JacRuntime, JacRuntimeInterface }
import from jaclang.runtimelib.memory { TieredMemory, VolatileMemory }
import from jaclang.runtimelib.serializer { Serializer }


obj _MemNode(Root) {
    has label: str = "";
}


test "tiered memory without L3 does not grow delete queue" {
    mem = TieredMemory(base_path=None, use_cache=False);
    for _ in range(200) {
        n = _MemNode(label="x");
        anchor = cast(NodeAnchor, n.__jac__);
        anchor.persistent = True;
        mem.put(anchor);
        mem.delete(anchor.id);
        mem.commit();
    }
    stats = mem.memory_stats();
    assert stats['gc_queue_count'] == 0 , (
        f"expected empty gc queue without L3, got {stats['gc_queue_count']}"
    );
    mem.close();
}


test "volatile memory delete queue drains on commit" {
    mem = VolatileMemory();
    for _ in range(50) {
        n = _MemNode(label="y");
        anchor = cast(NodeAnchor, n.__jac__);
        mem.put(anchor);
        mem.delete(anchor.id);
    }
    assert len(mem.get_gc()) == 0 , "volatile delete should not retain anchors";
    mem.commit();
    assert mem.memory_stats()['gc_queue_count'] == 0;
    mem.close();
}


test "ref_mode without persist does not grow L1 memory" {
    ctx = JacRuntimeInterface.create_j_context(user_root=None);
    JacRuntime.exec_ctx = ctx;
    try {
        nodes = [];
        for i in range(20) {
            n = _MemNode(label=f"n{i}");
            ctx.mem.put(cast(NodeAnchor, n.__jac__));
            nodes.append(n);
        }
        before = ctx.mem.memory_stats()['l1_count'];
        Serializer.begin_ref_mode_session();
        _ = Serializer.serialize(nodes, ref_mode=True);
        Serializer.end_ref_mode_session();
        after = ctx.mem.memory_stats()['l1_count'];
        assert after == before , (
            f"ref_mode should not pin extra anchors: before={before} after={after}"
        );
    } finally {
        ctx.close();
    }
}


test "unload_module removes dynamic registry entries" {
    src = """
    import from jaclang.jac0core.archetype { Root }
    obj DynN(Root) { has v: int = 1; }
    """;
    mod = JacRuntimeInterface.create_archetype_from_source(
        source_code=src,
        module_name="_dyn_test_mod",
        cachable=False
    );
    assert mod is not None;
    assert "_dyn_test_mod" in JacRuntime.loaded_modules;
    ok = JacRuntimeInterface.unload_module("_dyn_test_mod");
    assert ok;
    assert "_dyn_test_mod" not in JacRuntime.loaded_modules;
}
