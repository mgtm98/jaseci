"""Tests for TypeScript support in Jac client.

Uses session-scoped npm fixtures from conftest.py to avoid npm install overhead.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from jac_client.plugin.vite_client_bundle import ViteClientBundleBuilder
from jaclang.pycore.runtime import JacRuntime as Jac


def test_typescript_fixture_example(npm_cache_dir: Path, tmp_path: Path) -> None:
    """Test ts-support example project with TypeScript component."""
    # Get the source directory
    source_dir = Path(__file__).parent.parent / "examples" / "ts-support"

    # Copy the entire project directory (excluding large generated files)
    for item in source_dir.iterdir():
        if item.name in ("node_modules", "dist", "build", "compiled", "__pycache__"):
            continue
        dest = tmp_path / item.name
        if item.is_dir():
            shutil.copytree(item, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(item, dest)

    # Ensure jac.toml exists with minify: false for tests
    jac_toml = tmp_path / "jac.toml"
    if not jac_toml.exists():
        toml_content = """[project]
name = "ts-support"
version = "1.0.0"
description = "Jac application: ts-support"
entry-point = "app.jac"

[plugins.client.vite.build]
minify = false
"""
        jac_toml.write_text(toml_content)

    # Copy cached .jac-client.configs from npm_cache_dir
    source_configs = npm_cache_dir / ".jac-client.configs"
    dest_configs = tmp_path / ".jac-client.configs"
    if source_configs.exists():
        shutil.copytree(source_configs, dest_configs, symlinks=True)

    package_json = tmp_path / ".jac-client.configs" / "package.json"
    output_dir = tmp_path / "dist"
    output_dir.mkdir(parents=True, exist_ok=True)

    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the app from the copied ts-support project
    (module,) = Jac.jac_import("app", str(tmp_path), reload_module=True)

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    # Verify TypeScript component is referenced in bundle
    assert bundle.code is not None
    assert len(bundle.code) > 0

    # Verify TypeScript file was copied to compiled directory
    compiled_components = tmp_path / "compiled" / "components"
    compiled_button = compiled_components / "Button.tsx"
    assert compiled_button.exists(), "TypeScript file should be copied to compiled/"

    # Verify TypeScript file was copied to build directory
    build_components = tmp_path / "build" / "components"
    build_button = build_components / "Button.tsx"
    assert build_button.exists(), "TypeScript file should be copied to build/"

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()
