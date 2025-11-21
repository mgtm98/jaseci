from typing import Optional

from jaclang.runtimelib.machine import ExecutionContext


class JScaleExecutionContext(ExecutionContext):
    """Jac Scale Execution Context with custom memory backend."""

    def __init__(
        self,
        session: Optional[str] = None,
        root: Optional[str] = None,
    ) -> None:
        """Initialize JScaleExecutionContext."""
        print("JScaleExecutionContext initialized")
        # Call parent init which sets up mem, reports, system_root, etc.
        super().__init__(session, root)
