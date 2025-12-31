"""File covering plugin implementation."""
import os;
import pathlib;
import pickle;
import sys;
import from dotenv { load_dotenv }
import from jaclang.cli.cmdreg { CommandPriority, cmd_registry }
import from jaclang.pycore.runtime { ExecutionContext, hookimpl, plugin_manager }
import from jaclang.pycore.runtime { JacRuntime as Jac }
import from .context { JScaleExecutionContext }
import from .kubernetes.docker_impl { build_and_push_docker }
import from .kubernetes.K8s { deploy_K8s }
import from .kubernetes.utils { cleanup_K8s_resources }
import from .serve { JacAPIServer, EndpointMode }
"""Jac CLI."""
class JacCmd {
    """Create Jac CLI cmds."""
    @hookimpl
    static def create_cmd -> None {
        """Jac Scale functionality.""";
        @cmd_registry.register
        def scale(file_path: str, build: bool = False) -> None {
            if not os.path.exists(file_path) {
                raise FileNotFoundError(f"File not found: '{file_path}'") ;
            }
            code_folder = os.path.dirname(file_path) or '.';
            dotenv_path = os.path.join(code_folder, '.env');
            load_dotenv(dotenv_path);
            code_folder = os.path.relpath(code_folder);
            code_folder = pathlib.Path(code_folder).as_posix();
            base_file_path = os.path.basename(file_path);
            if build {
                build_and_push_docker(code_folder);
            }
            deploy_K8s(code_folder, base_file_path, build);
        }
        """Jac Destroys functionality.""";
        @cmd_registry.register
        def destroy(file_path: str) -> None {
            if not os.path.exists(file_path) {
                raise FileNotFoundError(f"File not found: '{file_path}'") ;
            }
            code_folder = os.path.dirname(file_path) or '.';
            dotenv_path = os.path.join(code_folder, '.env');
            load_dotenv(dotenv_path);
            cleanup_K8s_resources();
        }
        """Start a REST API server for the specified .jac file.

            Executes the target module and turns all functions into authenticated REST API
            endpoints. Function signatures are introspected to create the API interface.
            Walkers are converted to REST APIs where their fields become the interface,
            with an additional target_node field for spawning location.

            Each user gets their own persistent root node that persists across runs.
            Users must create an account and authenticate to access the API.

            Args:
                filename: Path to the .jac file to serve
                session: Session identifier for persistent state (default: auto-generated)
                port: Port to run the server on (default: 8000)
                main: Treat the module as __main__ (default: True)
                faux: Perform introspection and print endpoint docs without starting server (default: False)

            Examples:
                jac serve myprogram.jac
                jac serve myprogram.jac --port 8080
                jac serve myprogram.jac --session myapp.session
                jac serve myprogram.jac --faux
            """;
        @cmd_registry.register(priority=CommandPriority.PLUGIN, source='jac-scale')
        def serve(
            filename: str,
            session: str = '',
            port: int = 8000,
            main: bool = True,
            faux: bool = False,
            mode: str = 'all'
        ) -> None {
            import from jaclang.cli.cli { proc_file_sess }
            (base, mod, mach) = proc_file_sess(filename, session);
            lng = filename.split('.')[-1];
            Jac.set_base_path(base);
            if filename.endswith(('.jac', '.py')) {
                try {
                    Jac.jac_import(target=mod, base_path=base, lng=lng);
                } except Exception as e {
                    print(f"Error loading {filename}: {e}", file=sys.stderr);
                    mach.close();
                    <>exit(1);
                }
            } elif filename.endswith('.jir') {
                try {
                    with open(filename, 'rb') as f {
                        Jac.attach_program(pickle.load(f));
                        Jac.jac_import(target=mod, base_path=base, lng=lng);
                    }
                } except Exception as e {
                    print(f"Error loading {filename}: {e}", file=sys.stderr);
                    mach.close();
                    <>exit(1);
                }
            }
            session_path = session or os.path.join(base, f"{mod}.session");
            endpoint_mode = EndpointMode(mode) if mode in EndpointMode else EndpointMode.ALL;
            server = JacAPIServer(
                module_name=mod, 
                session_path=session_path, 
                port=port, 
                base_path=base,
                endpoint_mode=endpoint_mode
            );
            if faux {
                try {
                    server.print_endpoint_docs();
                    mach.close();
                    return;
                } except Exception as e {
                    print(
                        f"Error generating endpoint documentation: {e}",
                        file=sys.stderr
                    );
                    mach.close();
                    <>exit(1);
                }
            }
            try {
                server.start();
            } except KeyboardInterrupt {
                print('\nServer stopped.');
                mach.close();
            } except Exception as e {
                print(f"Server error: {e}", file=sys.stderr);
                mach.close();
                <>exit(1);
            }
        }

        """Start development servers with hot-reload for frontend and backend.

            Runs two separate servers on consecutive ports with file watching.
            Frontend server (port) handles pages, static files, and assets.
            Backend server (port+1) handles API, authentication, walkers, and functions.

            Args:
                filename: Path to the .jac file to serve
                session: Session identifier for persistent state (default: auto-generated)
                port: Base port number (frontend uses port, backend uses port+1, default: 8000)
                main: Treat the module as __main__ (default: True)
                faux: Unused for dev command

            Examples:
                jac dev myprogram.jac
                jac dev myprogram.jac --port 3000
                jac dev myprogram.jac --session myapp.session
            """;
        @cmd_registry.register(priority=CommandPriority.PLUGIN, source='jac-scale')
        def dev(
            filename: str,
            session: str = '',
            port: int = 8000,
            main: bool = True,
            faux: bool = False
        ) -> None {
            import subprocess;
            import threading;
            import time;
            import signal;
            try {
                import from watchfiles { watch }
            } except ImportError {
                print("Error: watchfiles package is required for dev mode.", file=sys.stderr);
                print("Install it with: pip install watchfiles", file=sys.stderr);
                <>exit(1);
            }
            
            base_path = os.path.dirname(os.path.abspath(filename)) or '.';
            dotenv_path = os.path.join(base_path, '.env');
            load_dotenv(dotenv_path);
            
            # Define ports
            ports = {
                'frontend': port,
                'backend': port + 1
            };
            
            # Server process tracking
            servers = {
                'frontend': None,
                'backend': None
            };
            
            # Flag to control watcher thread and main loop
            stop_watching = {'value': False};
            shutdown_requested = {'value': False};
            
            def start(mode: str) -> subprocess.Popen {
                cmd = [
                    sys.executable, '-m', 'jaclang', 'serve',
                    filename, '--port', str(ports[mode]), '--mode', mode
                ];
                if session {
                    cmd.extend(['--session', session]);
                }
                return subprocess.Popen(cmd, cwd=os.getcwd());
            }
            
            def reload(mode: str) -> None {
                if shutdown_requested['value'] {
                    return;
                }
                print(f"Reloading...");
                if servers[mode] {
                    servers[mode].terminate();
                    try {
                        servers[mode].wait(timeout=2);
                    } except subprocess.TimeoutExpired {
                        servers[mode].kill();
                        servers[mode].wait();
                    }
                }
                servers[mode] = start(mode);
            }
            
            def cleanup_servers() -> None {
                stop_watching['value'] = True;
                shutdown_requested['value'] = True;
                
                for mode in ['frontend', 'backend'] {
                    if servers[mode] {
                        servers[mode].terminate();
                        try {
                            servers[mode].wait(timeout=2);
                        } except subprocess.TimeoutExpired {
                            servers[mode].kill();
                            servers[mode].wait();
                        }
                        servers[mode] = None;
                    }
                }
            }

            servers['frontend'] = start('frontend');
            time.sleep(0.5);
            servers['backend'] = start('backend');
            
            # File extension sets
            frontend_exts = {
                '.html', '.htm', '.css', '.js', '.jsx', '.ts', '.tsx',
                '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.webp',
                '.woff', '.woff2', '.ttf', '.otf', '.eot'
            };
            backend_exts = {'.jac', '.py'};
            
            try {
                # Use watchfiles in the main loop instead of separate thread
                for changes in watch(base_path, recursive=True, debounce=1000, stop_event=None) {
                    if shutdown_requested['value'] {
                        break;
                    }
                    
                    # Check if processes are alive
                    if servers['frontend'] and servers['frontend'].poll() is not None {
                        print("[Frontend] Process stopped unexpectedly, restarting...");
                        servers['frontend'] = start('frontend');
                    }
                    if servers['backend'] and servers['backend'].poll() is not None {
                        print("[Backend] Process stopped unexpectedly, restarting...");
                        servers['backend'] = start('backend');
                    }
                    
                    frontend_changed = False;
                    backend_changed = False;
                    
                    for (change_type, changed_path) in changes {
                        ext = os.path.splitext(changed_path)[1].lower();
                        basename = os.path.basename(changed_path);
                        
                        if ext in frontend_exts {
                            if not frontend_changed {
                                print(f"\n[Frontend] Change detected: {basename}");
                                frontend_changed = True;
                            }
                        } elif ext in backend_exts {
                            if not backend_changed {
                                print(f"\n[Backend] Change detected: {basename}");
                                backend_changed = True;
                            }
                        }
                    }
                    
                    if frontend_changed {
                        reload('frontend');
                    }
                    if backend_changed {
                        reload('backend');
                    }
                }
            } except (KeyboardInterrupt, SystemExit) {

            } except Exception as e {
                if not shutdown_requested['value'] {
                    print(f"\nError: {e}", file=sys.stderr);
                }
            } finally {
                cleanup_servers();
            }
        }
    }
}

"""Jac Scale Plugin Implementation."""
class JacScalePlugin {
    @hookimpl
    static def create_j_context(
        session: (str | None) = None, <>root: (str | None) = None
    ) -> ExecutionContext {
        return JScaleExecutionContext(session=session, <>root=<>root);
    }
}

with entry {
    plugin_manager.register(JacScalePlugin());
}
