"""Tests for nested folder structure examples.

Uses session-scoped npm fixtures from conftest.py to avoid npm install overhead.
"""

from __future__ import annotations

from pathlib import Path

from jac_client.plugin.vite_client_bundle import ViteClientBundleBuilder
from jaclang.pycore.runtime import JacRuntime as Jac


def test_nested_advance_example(vite_project_with_antd: Path) -> None:
    """Test nested-advance example with multiple folder levels."""
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

    # Import the nested-advance example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "nested-folders" / "nested-advance"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    # Verify all expected components are in client_functions
    expected_exports = {
        "app",
        "ButtonRoot",
        "ButtonSecondL",
        "ButtonThirdL",
        "Card",
    }
    for export_name in expected_exports:
        assert export_name in bundle.client_functions, (
            f"Expected {export_name} to be in client_functions"
        )

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_nested_folder_structure_preserved(vite_project_with_antd: Path) -> None:
    """Test that nested folder structure is preserved in compiled/ directory."""
    temp_path = vite_project_with_antd
    package_json = temp_path / ".jac-client.configs" / "package.json"
    output_dir = temp_path / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the nested-advance example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "nested-folders" / "nested-advance"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Build the bundle (this creates files in compiled/)
    bundle = builder.build(module, force=True)

    # Verify bundle was created
    assert bundle is not None

    compiled_dir = temp_path / "compiled"

    # Verify root level file exists
    app_js = compiled_dir / "app.js"
    assert app_js.exists(), f"Expected {app_js} to exist in compiled/ directory"

    button_root_js = compiled_dir / "ButtonRoot.js"
    assert button_root_js.exists(), (
        f"Expected {button_root_js} to exist in compiled/ directory"
    )

    # Verify level1 files exist
    level1_dir = compiled_dir / "level1"
    assert level1_dir.exists(), f"Expected {level1_dir} directory to exist"

    button_second_js = level1_dir / "ButtonSecondL.js"
    assert button_second_js.exists(), (
        f"Expected {button_second_js} to exist in compiled/level1/ directory"
    )

    card_js = level1_dir / "Card.js"
    assert card_js.exists(), (
        f"Expected {card_js} to exist in compiled/level1/ directory"
    )

    # Verify level2 files exist
    level2_dir = level1_dir / "level2"
    assert level2_dir.exists(), f"Expected {level2_dir} directory to exist"

    button_third_js = level2_dir / "ButtonThirdL.js"
    assert button_third_js.exists(), (
        f"Expected {button_third_js} to exist in compiled/level1/level2/ directory"
    )

    # Cleanup
    builder.cleanup_temp_dir()


def test_relative_imports_in_compiled_files(vite_project_with_antd: Path) -> None:
    """Test that relative imports are preserved correctly in compiled files."""
    temp_path = vite_project_with_antd
    package_json = temp_path / ".jac-client.configs" / "package.json"
    output_dir = temp_path / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the nested-advance example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "nested-folders" / "nested-advance"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle was created
    assert bundle is not None

    compiled_dir = temp_path / "compiled"

    # Check that app.js imports from level1
    app_js_content = (compiled_dir / "app.js").read_text(encoding="utf-8")
    assert "level1/ButtonSecondL" in app_js_content, (
        "Expected app.js to import from level1/ButtonSecondL"
    )
    assert "level1/level2/ButtonThirdL" in app_js_content, (
        "Expected app.js to import from level1/level2/ButtonThirdL"
    )

    # Check that ButtonSecondL.js imports from root (using ..)
    button_second_content = (compiled_dir / "level1" / "ButtonSecondL.js").read_text(
        encoding="utf-8"
    )
    assert "../ButtonRoot" in button_second_content, (
        "Expected ButtonSecondL.js to import from ../ButtonRoot"
    )

    # Check that Card.js imports from both root and level2
    card_content = (compiled_dir / "level1" / "Card.js").read_text(encoding="utf-8")
    assert "../ButtonRoot" in card_content, (
        "Expected Card.js to import from ../ButtonRoot (above)"
    )
    assert "level2/ButtonThirdL" in card_content, (
        "Expected Card.js to import from level2/ButtonThirdL (below)"
    )

    # Check that ButtonThirdL.js imports from root and second level
    button_third_content = (
        compiled_dir / "level1" / "level2" / "ButtonThirdL.js"
    ).read_text(encoding="utf-8")
    assert "../../ButtonRoot" in button_third_content, (
        "Expected ButtonThirdL.js to import from ../../ButtonRoot"
    )
    assert "../ButtonSecondL" in button_third_content, (
        "Expected ButtonThirdL.js to import from ../ButtonSecondL"
    )

    # Cleanup
    builder.cleanup_temp_dir()


def test_nested_basic_example(vite_project_with_antd: Path) -> None:
    """Test nested-basic example with simpler nested structure."""
    temp_path = vite_project_with_antd
    package_json = temp_path / ".jac-client.configs" / "package.json"
    output_dir = temp_path / "dist"
    runtime_path = Path(__file__).parent.parent / "plugin" / "client_runtime.cl.jac"

    # Initialize the Vite builder
    builder = ViteClientBundleBuilder(
        runtime_path=runtime_path,
        vite_package_json=package_json,
        vite_output_dir=output_dir,
        vite_minify=False,
    )

    # Import the nested-basic example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "nested-folders" / "nested-basic"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    compiled_dir = temp_path / "compiled"

    # Verify nested structure is preserved
    components_dir = compiled_dir / "components"
    assert components_dir.exists(), (
        "Expected components directory to exist in compiled/"
    )

    button_js = components_dir / "button.js"
    assert button_js.exists(), "Expected button.js to exist in compiled/components/"

    # Cleanup
    builder.cleanup_temp_dir()
