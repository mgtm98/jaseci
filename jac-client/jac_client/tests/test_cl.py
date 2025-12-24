"""Tests for Vite client bundle generation.

These tests use session-scoped npm fixtures from conftest.py to avoid
running npm install for every test.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from jac_client.plugin.vite_client_bundle import ViteClientBundleBuilder
from jaclang.pycore.runtime import JacRuntime as Jac


def test_build_bundle_with_vite(vite_project_dir: Path) -> None:
    """Test that Vite bundling produces optimized output with proper structure."""
    package_json = vite_project_dir / ".jac-client.configs" / "package.json"
    output_dir = vite_project_dir / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module
    fixtures_dir = Path(__file__).parent / "fixtures" / "basic-app"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions
    assert "ButtonProps" in bundle.client_functions
    assert "API_LABEL" in bundle.client_globals
    assert len(bundle.hash) > 10

    # Verify bundle code contains expected content
    assert "function app()" in bundle.code
    assert 'API_LABEL = "Runtime Test";' in bundle.code

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Verify cached bundle is identical
    cached = builder.build(module, force=False)
    assert bundle.hash == cached.hash
    assert bundle.code == cached.code


def test_vite_bundle_without_package_json() -> None:
    """Test that missing package.json raises appropriate error."""
    fixtures_dir = Path(__file__).parent / "fixtures" / "basic-app"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Create builder without package.json
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=Path("/nonexistent/package.json"),
        vite_output_dir=Path("/tmp/output"),
    )

    # Building should raise an error
    with pytest.raises(Exception, match="Vite package.json not found"):
        builder.build(module, force=True)


def test_build_bundle_with_antd(vite_project_with_antd: Path) -> None:
    """Test that Vite bundling works with Ant Design components."""
    package_json = vite_project_with_antd / ".jac-client.configs" / "package.json"
    output_dir = vite_project_with_antd / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module with Ant Design
    fixtures_dir = Path(__file__).parent / "fixtures" / "client_app_with_antd"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "ButtonTest" in bundle.client_functions
    assert "CardTest" in bundle.client_functions
    assert "APP_NAME" in bundle.client_globals

    # Verify bundle code contains expected content
    assert "function ButtonTest()" in bundle.code
    assert "function CardTest()" in bundle.code
    assert 'APP_NAME = "Ant Design Test";' in bundle.code

    # verify antd components are present
    assert "ButtonGroup" in bundle.code

    # Verify the Ant Design fixture content is present
    assert "Testing Ant Design integration" in bundle.code

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_relative_import(vite_project_with_antd: Path) -> None:
    """Test that relative imports work correctly in Vite bundling."""
    package_json = vite_project_with_antd / ".jac-client.configs" / "package.json"
    output_dir = vite_project_with_antd / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module with relative import
    fixtures_dir = Path(__file__).parent / "fixtures" / "relative_import"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "RelativeImport" in bundle.client_functions
    assert "app" in bundle.client_functions
    assert "CustomButton" in bundle.code

    # Verify bundle code contains expected content
    assert "function RelativeImport()" in bundle.code
    assert "function app()" in bundle.code

    # Verify that the relative import (Button from .button) is properly resolved
    assert "ButtonGroup" in bundle.code

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_js_import(vite_project_dir: Path) -> None:
    """Test that JavaScript file imports work correctly in Vite bundling."""
    package_json = vite_project_dir / ".jac-client.configs" / "package.json"
    output_dir = vite_project_dir / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module with JavaScript import
    fixtures_dir = Path(__file__).parent / "fixtures" / "js_import"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "JsImportTest" in bundle.client_functions
    assert "app" in bundle.client_functions
    assert "JS_IMPORT_LABEL" in bundle.client_globals

    # Verify bundle code contains expected content
    assert "function JsImportTest()" in bundle.code
    assert "function app()" in bundle.code
    assert 'JS_IMPORT_LABEL = "JavaScript Import Test";' in bundle.code

    # Verify JavaScript imports are present in the bundle
    assert "formatMessage" in bundle.code
    assert "calculateSum" in bundle.code
    assert "JS_CONSTANT" in bundle.code
    assert "MessageFormatter" in bundle.code

    # Verify the JavaScript utility code is included
    assert "Hello," in bundle.code
    assert "Imported from JavaScript" in bundle.code

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_jsx_fragments_and_spread_props(vite_project_dir: Path) -> None:
    """Test that JSX fragments and spread props work correctly."""
    package_json = vite_project_dir / ".jac-client.configs" / "package.json"
    output_dir = vite_project_dir / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module with fragments and spread props
    fixtures_dir = Path(__file__).parent / "fixtures" / "test_fragments_spread"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "FragmentTest" in bundle.client_functions
    assert "SpreadPropsTest" in bundle.client_functions
    assert "MixedTest" in bundle.client_functions
    assert "NestedFragments" in bundle.client_functions

    # Verify spread props handling (Object.assign is used by compiler)
    assert "Object.assign" in bundle.code

    # Verify fragment test function exists
    assert "function FragmentTest()" in bundle.code

    # Verify spread props test function exists
    assert "function SpreadPropsTest()" in bundle.code

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_spawn_operator(vite_project_dir: Path) -> None:
    """Test that spawn operator generates correct __jacSpawn calls."""
    package_json = vite_project_dir / ".jac-client.configs" / "package.json"
    output_dir = vite_project_dir / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module with both spawn operator orderings
    fixtures_dir = Path(__file__).parent / "fixtures" / "spawn_test"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    # Verify complete __jacSpawn calls for root spawn scenarios
    assert '__jacSpawn("test_walker", "", {})' in bundle.code
    assert '__jacSpawn("parameterized_walker", "", {' in bundle.code
    assert '"value": 42' in bundle.code

    # Reverse order spawn
    assert re.search(
        r'__jacSpawn\("test_walker",\s*"",\s*\{[^}]*"message":\s*"Reverse spawn!"[^}]*\}\)',
        bundle.code,
    )

    # Verify UUID spawn scenarios
    assert '__jacSpawn("test_walker", node_id, {})' in bundle.code
    assert '"550e8400-e29b-41d4-a716-446655440000"' in bundle.code

    assert re.search(
        r'__jacSpawn\("parameterized_walker",\s*another_node_id,\s*\{[^}]*"value":\s*100[^}]*\}\)',
        bundle.code,
    )
    assert '"6ba7b810-9dad-11d1-80b4-00c04fd430c8"' in bundle.code

    # Verify positional argument mapping
    assert re.search(
        r'__jacSpawn\("positional_walker",\s*node_id,\s*\{[^}]*"label":\s*"Node positional"[^}]*"count":\s*2',
        bundle.code,
    )

    # Verify spread handling
    assert re.search(
        r'__jacSpawn\("positional_walker",\s*"",\s*_objectSpread\(\{\s*"label":\s*"Spread order"[^}]*"count":\s*5\s*\},\s*extra_fields\)',
        bundle.code,
    )

    assert bundle.code.count("__jacSpawn") >= 7

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_serve_cl_file(vite_project_dir: Path) -> None:
    """Test that serving a .cl file works correctly."""
    package_json = vite_project_dir / ".jac-client.configs" / "package.json"
    output_dir = vite_project_dir / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the test module
    fixtures_dir = Path(__file__).parent / "fixtures" / "cl_file"
    (module,) = Jac.jac_import("app", str(fixtures_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    assert "function app()" in bundle.code
    assert '__jacJsx("div", {}, [__jacJsx("h2", {}, ["My Todos"])' in bundle.code
    assert "root.render(/* @__PURE__ */ React.c" in bundle.code
    assert "ar _useState = reactExports.useState([]), _useStat" in bundle.code
    assert 'turn __jacSpawn("create_todo", ' in bundle.code

    # Cleanup
    builder.cleanup_temp_dir()
