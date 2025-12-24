"""Tests for asset-serving and css-styling examples.

Uses session-scoped npm fixtures from conftest.py to avoid npm install overhead.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from jac_client.plugin.vite_client_bundle import ViteClientBundleBuilder
from jaclang.pycore.runtime import JacRuntime as Jac


def test_image_asset_example(vite_project_dir: Path) -> None:
    """Test image-asset example with static asset paths."""
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

    # Import the image-asset example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "asset-serving" / "image-asset"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    # Verify image path is in the bundle
    assert "/static/assets/burger.png" in bundle.code

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_css_with_image_example(vite_project_dir: Path) -> None:
    """Test css-with-image example with CSS and image assets."""
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

    # Import the css-with-image example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "asset-serving" / "css-with-image"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    # Verify CSS import is present (CSS should be extracted to separate file)
    assert "import" in bundle.code.lower()

    # Verify image paths are in the bundle
    assert "/static/assets/burger.png" in bundle.code

    # Verify CSS file was extracted
    css_files = list(output_dir.glob("*.css"))
    assert len(css_files) > 0, "Expected at least one CSS file"

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()


def test_import_alias_example(vite_project_dir: Path) -> None:
    """Test import-alias example with @jac-client/assets alias."""
    temp_path = vite_project_dir
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

    # Import the import-alias example
    examples_dir = (
        Path(__file__).parent.parent / "examples" / "asset-serving" / "import-alias"
    )
    (module,) = Jac.jac_import("app", str(examples_dir))

    # Copy assets from example directory to temp project's compiled/assets/
    # This is needed because @jac-client/assets alias points to compiled/assets
    example_assets_dir = examples_dir / "assets"
    temp_assets_dir = temp_path / "compiled" / "assets"
    if example_assets_dir.exists():
        temp_assets_dir.mkdir(parents=True, exist_ok=True)
        # Copy all files from example assets to temp assets
        for asset_file in example_assets_dir.iterdir():
            if asset_file.is_file():
                shutil.copy2(asset_file, temp_assets_dir / asset_file.name)

    # Build the bundle
    bundle = builder.build(module, force=True)

    # Verify bundle structure
    assert bundle is not None
    assert bundle.module_name == "app"
    assert "app" in bundle.client_functions

    # Verify bundle was written to output directory
    bundle_files = list(output_dir.glob("client.*.js"))
    assert len(bundle_files) > 0, "Expected at least one bundle file"

    # Cleanup
    builder.cleanup_temp_dir()
