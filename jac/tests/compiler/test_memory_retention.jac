"""Compiler cache eviction regression tests."""

import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.jac0core.program { JacProgram }


test "invalidate_module drops mtir scopes for module" {
    with TemporaryDirectory() as tmp {
        mod_file = Path(tmp) / "sample.jac";
        mod_file.write_text("obj N { has x: int = 0; }");
        resolved = str(mod_file.resolve());
        prog = JacProgram();
        bucket = set();
        bucket.add("sample.fn");
        prog._mtir_scopes_by_module[resolved] = bucket;
        prog._mtir_scope_modules["sample.fn"] = resolved;
        prog.invalidate_module(resolved);
        assert resolved not in prog._mtir_scopes_by_module;
        assert "sample.fn" not in prog._mtir_scope_modules;
    }
}
