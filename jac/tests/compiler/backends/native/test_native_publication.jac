import os;
import subprocess;
import tempfile;
import from pathlib { Path }
import from unittest.mock { patch }
import jaclang.jac0core.cache_paths as cache_paths;
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.backends.native.link_plan {
    ArtifactKind,
    build_link_plan,
    link_artifact
}

test "failed atomic publication preserves the destination and removes its temporary file" {
    with tempfile.TemporaryDirectory() as directory {
        target = Path(directory) / "product";
        target.write_bytes(b"previous product");
        failed = False;
        with patch.object(
            cache_paths.os, "replace", side_effect=OSError("publication failed")
        ) {
            try {
                cache_paths.atomic_write(target, b"replacement product");
            } except OSError {
                failed = True;
            }
        }
        assert failed;
        assert target.read_bytes() == b"previous product";
        assert list(Path(directory).iterdir()) == [target];
    }
}

test "atomic publication preserves existing file permissions" {
    if os.name == "nt" {
        return;
    }
    with tempfile.TemporaryDirectory() as directory {
        target = Path(directory) / "private_cache";
        target.write_bytes(b"old");
        target.chmod(0o640);
        cache_paths.atomic_write(target, b"new");
        assert target.read_bytes() == b"new";
        assert target.stat().st_mode & 0o777 == 0o640;
    }
}

test "rebuilding a native executable preserves its open previous image" {
    if os.name == "nt" {
        return;
    }
    with tempfile.TemporaryDirectory() as directory {
        source = Path(directory) / "main.jac";
        output = Path(directory) / "program";
        source.write_text("with entry { print(7); }\n");
        options = CompileOptions(
            aot_mode=True,
            default_codespace="native",
            skip_native_engine=True,
            memory_profile="nogc"
        );
        first = JacProgram();
        first.options = options;
        plan = build_link_plan(first, [str(source)], options);
        link_artifact(plan, str(output), ArtifactKind.EXECUTABLE);
        original = output.read_bytes();
        with output.open("rb") as previous {
            source.write_text("with entry { print(8); }\n");
            second = JacProgram();
            second.options = options;
            replacement = build_link_plan(second, [str(source)], options);
            link_artifact(replacement, str(output), ArtifactKind.EXECUTABLE);
            assert output.read_bytes() != original;
            assert previous.read() == original , "rebuilding changed an already-open executable image";
            assert os.fstat(previous.fileno()).st_ino != output.stat().st_ino;
        }
        result = subprocess.run([str(output)], capture_output=True, text=True);
        assert result.returncode == 0 , result.stderr;
        assert result.stdout.strip() == "8";
    }
}
