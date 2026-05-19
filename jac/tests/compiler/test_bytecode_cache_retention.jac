"""Bytecode cache retention regression tests (compile + unload cycles)."""

import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from typing { cast }
import from jaclang.jac0core.program { JacProgram }
import from jaclang.jac0core.runtime { JacRuntime, JacRuntimeInterface }


test "repeated compile on same file keeps hub bounded" {
    with TemporaryDirectory() as tmp {
        mod_file = Path(tmp) / "loop.jac";
        mod_file.write_text("with entry { glob x: int = 1; }");
        resolved = str(mod_file.resolve());
        prog = JacProgram();
        compiler = prog._get_compiler();
        for _ in range(5) {
            prog.compile(resolved, type_check=False);
            _ = compiler.get_bytecode(resolved, prog);
        }
        snap = prog.memory_snapshot();
        assert snap['hub_modules'] <= 1 , (
            f"expected single hub entry, got {snap['hub_modules']}"
        );
    }
}


test "unload clears hub and native caches for dynamic module aliases" {
    src = """
    import from jaclang.jac0core.archetype { Root }
    obj DynX(Root) { has n: int = 0; }
    """;
    mod = JacRuntimeInterface.create_archetype_from_source(
        source_code=src,
        module_name="_dyn_alias_test",
        cachable=False
    );
    assert mod is not None;
    prog = JacRuntime.program;
    assert prog is not None;
    before_hub = prog.memory_snapshot()['hub_modules'];
    assert before_hub >= 1;
    assert "_dyn_alias_test" in JacRuntime.loaded_modules;
    stem = JacRuntime.dynamic_module_aliases.get("_dyn_alias_test");
    if stem {
        assert stem in JacRuntime.loaded_modules;
    }
    ok = JacRuntimeInterface.unload_module("_dyn_alias_test");
    assert ok;
    assert "_dyn_alias_test" not in JacRuntime.loaded_modules;
    if stem {
        assert stem not in JacRuntime.loaded_modules;
    }
    after = prog.memory_snapshot();
    assert after['hub_modules'] == 0 , (
        f"hub should be empty after unload, got {after['hub_modules']}"
    );
    assert after['native_cache'] == 0;
}
