"""Command line interface tool for the Jac Client."""

import os
import re
import subprocess
import sys

from jaclang.cli.cmdreg import cmd_registry
from jaclang.pycore.runtime import hookimpl


class JacCmd:
    """Jac CLI."""

    @staticmethod
    @hookimpl
    def create_cmd() -> None:
        """Create Jac CLI cmds."""

        @cmd_registry.register
        def create_jac_app(name: str) -> None:
            """Create a new Jac application with npm and Vite setup.

            Bootstraps a new Jac project by creating a temporary directory, initializing
            npm, installing Vite, and setting up the basic project structure.

            Args:
                name: Name of the project to create

            Examples:
                jac create_jac_app my-app
                jac create_jac_app my-jac-project
            """
            if not name:
                print(
                    "Error: Project name is required. Use --name=your-project-name",
                    file=sys.stderr,
                )
                exit(1)

            # Validate project name (basic npm package name validation)
            if not re.match(r"^[a-zA-Z0-9_-]+$", name):
                print(
                    "Error: Project name must contain only letters, numbers, hyphens, and underscores",
                    file=sys.stderr,
                )
                exit(1)

            print(f"Creating new Jac application: {name}")

            # Create project directory in current working directory
            project_path = os.path.join(os.getcwd(), name)

            if os.path.exists(project_path):
                print(
                    f"Error: Directory '{name}' already exists in current location",
                    file=sys.stderr,
                )
                exit(1)

            os.makedirs(project_path, exist_ok=True)

            try:
                # Change to project directory
                original_cwd = os.getcwd()
                os.chdir(project_path)

                # create compiled folder for transpiled files
                compiled_folder = os.path.join(project_path, "compiled")
                os.makedirs(compiled_folder, exist_ok=True)

                # create build folder
                build_folder = os.path.join(project_path, "build")
                os.makedirs(build_folder, exist_ok=True)

                # create assets folder for static assets (images, fonts, etc.)
                assets_folder = os.path.join(project_path, "assets")
                os.makedirs(assets_folder, exist_ok=True)

                # Create jac.toml with project configuration
                toml_content = f'''[project]
name = "{name}"
version = "1.0.0"
description = "Jac application: {name}"
entry-point = "app.jac"
'''

                # Write jac.toml
                config_file_path = os.path.join(project_path, "jac.toml")
                with open(config_file_path, "w") as f:
                    f.write(toml_content)

                print("Created jac.toml with project configuration")

                # Create basic project structure
                print("Setting up project structure...")

                # Prepare app.jac content with TypeScript support (enabled by default)
                main_jac_content = """
# Pages
cl import from react {useState, useEffect}
cl import from ".components/Button.tsx" { Button }

cl {
    def app() -> any {
        [count, setCount] = useState(0);
        useEffect(lambda -> None {
            console.log("Count: ", count);
        }, [count]);
        return <div style={{padding: "2rem", fontFamily: "Arial, sans-serif"}}>
            <h1>Hello, World!</h1>
            <p>Count: {count}</p>
            <div style={{display: "flex", gap: "1rem", marginTop: "1rem"}}>
                <Button
                    label="Increment"
                    onClick={lambda -> None {setCount(count + 1);}}
                    variant="primary"
                />
                <Button
                    label="Reset"
                    onClick={lambda -> None {setCount(0);}}
                    variant="secondary"
                />
            </div>
        </div>;
    }
}
"""

                # Create app.jac file
                with open(os.path.join(project_path, "app.jac"), "w") as f:
                    f.write(main_jac_content)

                # Note: vite.config.js and tsconfig.json will be generated automatically
                # in .jac-client.configs/ during the first bundling process (when running jac serve)

                # Create components directory with a sample TypeScript component
                components_dir = os.path.join(project_path, "components")
                os.makedirs(components_dir, exist_ok=True)

                button_component_content = """import React from 'react';

interface ButtonProps {
  label: string;
  onClick?: () => void;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
}

export const Button: React.FC<ButtonProps> = ({
  label,
  onClick,
  variant = 'primary',
  disabled = false
}) => {
  const baseStyles: React.CSSProperties = {
    padding: '0.75rem 1.5rem',
    fontSize: '1rem',
    fontWeight: '600',
    borderRadius: '0.5rem',
    border: 'none',
    cursor: disabled ? 'not-allowed' : 'pointer',
    transition: 'all 0.2s ease',
  };

  const variantStyles: Record<string, React.CSSProperties> = {
    primary: {
      backgroundColor: disabled ? '#9ca3af' : '#3b82f6',
      color: '#ffffff',
    },
    secondary: {
      backgroundColor: disabled ? '#e5e7eb' : '#6b7280',
      color: '#ffffff',
    },
  };

  return (
    <button
      style={{ ...baseStyles, ...variantStyles[variant] }}
      onClick={onClick}
      disabled={disabled}
    >
      {label}
    </button>
  );
};

export default Button;
"""
                with open(os.path.join(components_dir, "Button.tsx"), "w") as f:
                    f.write(button_component_content)

                # Create README.md
                readme_content = f"""# {name}

## Running Jac Code

Make sure node modules are installed:
```bash
npm install
```

To run your Jac code, use the Jac CLI:

```bash
jac serve app.jac
```

## TypeScript Support

This project includes TypeScript support by default. You can create TypeScript components in the `components/` directory and import them in your Jac files.

Example:
```jac
cl import from ".components/Button.tsx" {{ Button }}
```

See `components/Button.tsx` for an example TypeScript component.

The `tsconfig.json` file is automatically generated during build time.

For more information, see the [TypeScript guide](../../docs/working-with-ts.md).

Happy coding with Jac and TypeScript!
"""

                with open(os.path.join(project_path, "README.md"), "w") as f:
                    f.write(readme_content)

                # Create .gitignore file
                gitignore_content = """node_modules
app.session.bak
app.session.dat
app.session.dir
app.session.users.json
compiled/
.jac-client.configs/
"""
                with open(os.path.join(project_path, ".gitignore"), "w") as f:
                    f.write(gitignore_content)

                # Return to original directory
                os.chdir(original_cwd)

                print(f"Successfully created Jac application '{name}'!")
                print(f"Project location: {os.path.abspath(project_path)}")
                print("\nNext steps:")
                print(f"  cd {name}")
                print("  jac serve app.jac")

            except subprocess.CalledProcessError as e:
                # Return to original directory on error
                os.chdir(original_cwd)
                print(f"Error running npm command: {e}", file=sys.stderr)
                print(f"Command output: {e.stdout}", file=sys.stderr)
                print(f"Command error: {e.stderr}", file=sys.stderr)
                exit(1)
            except Exception as e:
                # Return to original directory on error
                os.chdir(original_cwd)
                print(f"Error creating project: {e}", file=sys.stderr)
                exit(1)

        # Note: The add and remove commands for --cl are now handled by core CLI
        # via the dependency registry. The plugin_config.py registers handlers for
        # the "npm" dependency type which are called when --cl flag is used.
