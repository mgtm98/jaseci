"""File covering plugin implementation."""
import os;
import pathlib;
import pickle;
import sys;
import from dotenv { load_dotenv }
import from jaclang.cli.cmdreg { CommandPriority, cmd_registry }
import from jaclang.pycore.runtime { hookimpl, plugin_manager }
import from jaclang.runtimelib.context { ExecutionContext }
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
        @cmd_registry.register(priority=CommandPriority.PLUGIN, source='jac-scale')
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
        @cmd_registry.register(priority=CommandPriority.PLUGIN, source='jac-scale')
        def destroy(file_path: str) -> None {
            if not os.path.exists(file_path) {
                raise FileNotFoundError(f"File not found: '{file_path}'") ;
            }
            code_folder = os.path.dirname(file_path) or '.';
            dotenv_path = os.path.join(code_folder, '.env');
            load_dotenv(dotenv_path);
            cleanup_K8s_resources();
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

    @hookimpl
    static def create_server(
        module_name: str,
        session_path: str,
        port: int,
        base_path: str,
        mode: str,
        backend_url: str = None
    ) -> 'JacAPIServer' {
        return JacAPIServer(
            module_name=module_name,
            session_path=session_path,
            port=port,
            base_path=base_path,
            endpoint_mode=mode
        );
    }
}

# Pluggy's varnames() puts parameters with defaults into kwargnames, not argnames.
# But _multicall only passes argnames to hook implementations.
# JacRuntimeInterfaceImpl strips defaults via generate_plugin_helpers, so we must too.
import inspect;
glob func = JacScalePlugin.create_j_context,
     sig = inspect.signature(func),
     sig_nodef = sig.replace(
         parameters=[
             p.replace(default=inspect.Parameter.empty)
             for p in sig.parameters.values()
         ]
     ),
     func2 = JacScalePlugin.create_server,
     sig2 = inspect.signature(func2),
     sig_nodef2 = sig2.replace(
         parameters=[
             p.replace(default=inspect.Parameter.empty)
             for p in sig2.parameters.values()
         ]
     );

with entry {
    func.__signature__ = sig_nodef;
    func2.__signature__ = sig_nodef2;
    plugin_manager.register(JacScalePlugin());
}
