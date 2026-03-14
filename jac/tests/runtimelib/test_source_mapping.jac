"""Tests for the centralized source mapping utility."""

import json;
import os;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.runtimelib.source_mapping {
    SourceMapper,
    SourceMap,
    _decode_vlq,
    _parse_mappings,
    _scan_source_comments,
    read_source_snippet
}

# =============================================================================
# VLQ Decoding
# =============================================================================
test "vlq decodes simple values" {
    assert _decode_vlq("A") == [0];
    assert _decode_vlq("C") == [1];
    assert _decode_vlq("D") == [-1];
    assert _decode_vlq("K") == [5];
}

test "vlq decodes multi-value segment" {
    # A segment with 4 fields: gen_col, src_idx, src_line, src_col
    values = _decode_vlq("AACA");
    assert len(values) == 4;
    assert values[0] == 0;  # gen_col delta
    assert values[1] == 0;  # src_idx delta
    assert values[2] == 1;  # src_line delta
    assert values[3] == 0;  # src_col delta
}

# =============================================================================
# Source Comment Scanning
# =============================================================================
test "scan finds source comments in compiled JS" {
    with TemporaryDirectory() as tmpdir {
        compiled = Path(tmpdir) / "compiled";
        compiled.mkdir();
        (compiled / "main.js").write_text(
            "/* Source: /project/main.jac */\nvar x = 1;\n"
        );
        (compiled / "utils.js").write_text(
            "/* Source: /project/utils.jac */\nfunction f() {}\n"
        );
        # File without comment
        (compiled / "vendor.js").write_text("var y = 2;\n");
        comments = _scan_source_comments(compiled);
        assert any("/project/main.jac" in v for v in comments.values());
        assert any("/project/utils.jac" in v for v in comments.values());
        assert not any("vendor" in v for v in comments.values());
    }
}

test "scan handles subdirectories" {
    with TemporaryDirectory() as tmpdir {
        compiled = Path(tmpdir) / "compiled";
        components = compiled / "components";
        components.mkdir(parents=True);
        (components / "Button.js").write_text(
            "/* Source: /project/components/Button.cl.jac */\n"
        );
        comments = _scan_source_comments(compiled);
        assert any("Button.cl.jac" in v for v in comments.values());
    }
}

# =============================================================================
# Source Map Resolution
# =============================================================================
"""Create a minimal but realistic source map for testing."""
def _create_test_source_map(tmpdir: str) -> str {
    compiled_dir = Path(tmpdir) / ".jac" / "client" / "compiled";
    dist_dir = Path(tmpdir) / ".jac" / "client" / "dist";
    compiled_dir.mkdir(parents=True);
    dist_dir.mkdir(parents=True);

    (compiled_dir / "main.js").write_text(
        "/* Source: /project/main.jac */\nfunction app() { return 1; }\n"
    );
    (compiled_dir / "feed.js").write_text(
        "/* Source: /project/frontend/feed.jac */\nfunction feed() {}\n"
    );

    source_map = {
        "version": 3,
        "file": "client.abc123.js",
        "sources": ["../compiled/main.js", "../compiled/feed.js"],
        "names": [],
        "mappings": "AAAA;;;;ACGA"
    };
    map_path = dist_dir / "client.abc123.js.map";
    map_path.write_text(json.dumps(source_map));
    return tmpdir;
}

test "resolve to jac file" {
    with TemporaryDirectory() as tmpdir {
        _create_test_source_map(tmpdir);
        mapper = SourceMapper.from_bundle(tmpdir);
        loc = mapper.resolve(1, 0);
        assert loc is not None;
        assert "main.jac" in loc.file;
        assert loc.line == 1;
    }
}

test "resolve second source" {
    with TemporaryDirectory() as tmpdir {
        _create_test_source_map(tmpdir);
        mapper = SourceMapper.from_bundle(tmpdir);
        loc = mapper.resolve(5, 0);
        assert loc is not None;
        assert "feed.jac" in loc.file;
        assert loc.line == 4;  # src_line=3 -> 1-indexed = 4
    }
}

test "resolve returns none for invalid line" {
    with TemporaryDirectory() as tmpdir {
        _create_test_source_map(tmpdir);
        mapper = SourceMapper.from_bundle(tmpdir);
        assert mapper.resolve(9999, 0) is None;
        assert mapper.resolve(0, 0) is None;
    }
}

test "resolve without source map returns none" {
    mapper = SourceMapper();
    assert mapper.resolve(1, 0) is None;
}

# =============================================================================
# Stack Trace Resolution
# =============================================================================
"""Create a SourceMapper with a minimal source map."""
def _create_mapper_with_map(tmpdir: str) -> SourceMapper {
    compiled_dir = Path(tmpdir) / ".jac" / "client" / "compiled";
    dist_dir = Path(tmpdir) / ".jac" / "client" / "dist";
    compiled_dir.mkdir(parents=True);
    dist_dir.mkdir(parents=True);

    (compiled_dir / "main.js").write_text("/* Source: /project/main.jac */\n");

    source_map = {
        "version": 3,
        "file": "client.js",
        "sources": ["../compiled/main.js"],
        "names": [],
        "mappings": "AAAA"
    };
    (dist_dir / "client.hash.js.map").write_text(json.dumps(source_map));
    return SourceMapper.from_bundle(tmpdir);
}

test "resolve stack trace to jac files" {
    with TemporaryDirectory() as tmpdir {
        mapper = _create_mapper_with_map(tmpdir);
        stack = "TypeError: Cannot read property\n" + "    at MyComponent (http://localhost:8001/static/client.js:1:0)\n" + "    at React.render (http://localhost:8001/static/client.js:1:100)";
        resolved = mapper.resolve_stack_trace(stack);
        assert "main.jac" in resolved;
        assert "TypeError: Cannot read property" in resolved;
    }
}

test "node modules not resolved" {
    mapper = SourceMapper();
    stack = "    at React.createElement (node_modules/react/index.js:1:0)";
    assert mapper.resolve_stack_trace(stack) == stack;
}

test "no source map returns original stack" {
    mapper = SourceMapper();
    stack = "    at foo (client.js:1:0)";
    assert mapper.resolve_stack_trace(stack) == stack;
}

# =============================================================================
# Source Snippet Reader
# =============================================================================
test "read source snippet around target line" {
    with TemporaryDirectory() as tmpdir {
        f = Path(tmpdir) / "test.jac";
        f.write_text("line1\nline2\nline3\nline4\nline5\n");
        snippet = read_source_snippet(str(f), 3, context_lines=1);
        assert "line2" in snippet;
        assert "line3" in snippet;
        assert "line4" in snippet;
        assert " -> " in snippet;
    }
}

test "read source snippet returns empty for missing file" {
    assert read_source_snippet("/nonexistent/file.jac", 1) == "";
}

test "read source snippet handles edge case" {
    with TemporaryDirectory() as tmpdir {
        f = Path(tmpdir) / "test.jac";
        f.write_text("one line\n");
        snippet = read_source_snippet(str(f), 1);
        assert "one line" in snippet;
    }
}
