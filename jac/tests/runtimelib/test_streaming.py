"""Test for jac-scale serve command and REST API server."""

import contextlib
import gc
import glob
import socket
import subprocess
import time
from pathlib import Path
from typing import Any, cast

import requests


def get_free_port() -> int:
    """Get a free port by binding to port 0 and releasing it."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.listen(1)
        port = s.getsockname()[1]
    return port


class TestJacScaleServe:
    """Test jac-scale serve REST API functionality."""

    # Class attributes with type annotations
    fixtures_dir: Path
    test_file: Path
    port: int
    base_url: str
    server_process: subprocess.Popen[str] | None = None

    @classmethod
    def setup_class(cls) -> None:
        """Set up test class - runs once for all tests."""
        cls.fixtures_dir = Path(__file__).parent / "fixtures"
        cls.test_file = cls.fixtures_dir / "serve_api.jac"

        # Ensure fixture file exists
        if not cls.test_file.exists():
            raise FileNotFoundError(f"Test fixture not found: {cls.test_file}")

        # Use dynamically allocated free port
        cls.port = get_free_port()
        cls.base_url = f"http://localhost:{cls.port}"

        # Clean up any existing database files before starting
        cls._cleanup_db_files()

        # Start the server process
        cls.server_process = None
        cls._start_server()

    @classmethod
    def teardown_class(cls) -> None:
        """Tear down test class - runs once after all tests."""
        # Stop server process
        if cls.server_process:
            cls.server_process.terminate()
            try:
                cls.server_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                cls.server_process.kill()
                cls.server_process.wait()

        # Give the server a moment to fully release file handles
        time.sleep(0.5)
        # Run garbage collection to clean up lingering socket objects
        gc.collect()

        # Clean up database files
        cls._cleanup_db_files()

    @classmethod
    def _start_server(cls) -> None:
        """Start the jac-scale server in a subprocess."""
        import sys

        # Get the jac executable from the same directory as the current Python interpreter
        jac_executable = Path(sys.executable).parent / "jac"

        # Build the command to start the server
        cmd = [
            str(jac_executable),
            "start",
            str(cls.test_file),
            "--port",
            str(cls.port),
        ]

        # Start the server process
        cls.server_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # Wait for server to be ready
        max_attempts = 50
        server_ready = False

        for _ in range(max_attempts):
            # Check if process has died
            if cls.server_process.poll() is not None:
                # Process has terminated, get output
                stdout, stderr = cls.server_process.communicate()
                raise RuntimeError(
                    f"Server process terminated unexpectedly.\n"
                    f"STDOUT: {stdout}\nSTDERR: {stderr}"
                )

            try:
                # Try to connect to any endpoint to verify server is up
                # Use /docs which should exist in FastAPI
                response = requests.get(f"{cls.base_url}/docs", timeout=2)
                if response.status_code in (200, 404):  # Server is responding
                    print(f"Server started successfully on port {cls.port}")
                    server_ready = True
                    break
            except (requests.ConnectionError, requests.Timeout):
                time.sleep(2)

        # If we get here and server is not ready, it failed to start
        if not server_ready:
            # Try to terminate the process
            cls.server_process.terminate()
            try:
                stdout, stderr = cls.server_process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                cls.server_process.kill()
                stdout, stderr = cls.server_process.communicate()

            raise RuntimeError(
                f"Server failed to start after {max_attempts} attempts.\n"
                f"STDOUT: {stdout}\nSTDERR: {stderr}"
            )

    @classmethod
    def _cleanup_db_files(cls) -> None:
        """Delete SQLite database files and legacy shelf files."""
        import shutil

        # Clean up SQLite database files (WAL mode creates -wal and -shm files)
        for pattern in [
            "*.db",
            "*.db-wal",
            "*.db-shm",
            # Legacy shelf files
            "anchor_store.db.dat",
            "anchor_store.db.bak",
            "anchor_store.db.dir",
        ]:
            for db_file in glob.glob(pattern):
                with contextlib.suppress(Exception):
                    Path(db_file).unlink()

        # Clean up database files in fixtures directory
        for pattern in ["*.db", "*.db-wal", "*.db-shm"]:
            for db_file in glob.glob(str(cls.fixtures_dir / pattern)):
                with contextlib.suppress(Exception):
                    Path(db_file).unlink()

        # Clean up .jac directory created during serve
        client_build_dir = cls.fixtures_dir / ".jac"
        if client_build_dir.exists():
            with contextlib.suppress(Exception):
                shutil.rmtree(client_build_dir)

    @staticmethod
    def _extract_transport_response_data(
        json_response: dict[str, Any] | list[Any],
    ) -> dict[str, Any] | list[Any]:
        """Extract data from TransportResponse envelope format.

        Handles both success and error responses.
        """
        # Handle jac-scale's tuple response format [status, body]
        if isinstance(json_response, list) and len(json_response) == 2:
            body: dict[str, Any] = json_response[1]
            json_response = body

        # Handle TransportResponse envelope format
        # If response has 'ok', 'type', 'data', 'error' keys, extract data/error
        if (
            isinstance(json_response, dict)
            and "ok" in json_response
            and "data" in json_response
        ):
            if json_response.get("ok") and json_response.get("data") is not None:
                # Success case: return the data field
                return json_response["data"]
            elif not json_response.get("ok") and json_response.get("error"):
                # Error case: return error info in a format tests expect
                error_info = json_response["error"]
                result: dict[str, Any] = {
                    "error": error_info.get("message", "Unknown error")
                }
                if "code" in error_info:
                    result["error_code"] = error_info["code"]
                if "details" in error_info:
                    result["error_details"] = error_info["details"]
                return result

        # FastAPI validation errors (422) have "detail" field - return as-is
        # These come from Pydantic validation before our endpoint is called
        return json_response

    def _request(
        self,
        method: str,
        path: str,
        data: dict[str, Any] | None = None,
        token: str | None = None,
        timeout: int = 5,
        max_retries: int = 60,
        retry_interval: float = 2.0,
    ) -> dict[str, Any]:
        """Make HTTP request to server and return JSON response.

        Retries on 503 Service Unavailable responses.
        """
        url = f"{self.base_url}{path}"
        headers = {"Content-Type": "application/json"}

        if token:
            headers["Authorization"] = f"Bearer {token}"

        response = None
        for attempt in range(max_retries):
            response = requests.request(
                method=method,
                url=url,
                json=data,
                headers=headers,
                timeout=timeout,
            )

            if response.status_code == 503:
                print(
                    f"[DEBUG] {path} returned 503, retrying ({attempt + 1}/{max_retries})..."
                )
                time.sleep(retry_interval)
                continue

            break

        assert response is not None, "No response received"
        json_response: Any = response.json()
        return self._extract_transport_response_data(json_response)  # type: ignore[return-value]

    def test_function_streaming(self) -> None:
        """Test streaming function with SSE format."""
        # Create user
        create_response = requests.post(
            f"{self.base_url}/user/register",
            json={"username": "functionStreaming", "password": "password123"},
            timeout=5,
        )
        create_data = cast(
            dict[str, Any],
            self._extract_transport_response_data(create_response.json()),
        )
        token = create_data["token"]

        response = requests.post(
            f"{self.base_url}/function/stream_numbers",
            json={"count": 3},
            timeout=30,
            stream=True,
            headers={"Authorization": f"Bearer {token}"},
        )

        assert response.status_code == 200
        assert response.headers["content-type"] == "text/event-stream"
        assert response.headers.get("cache-control") == "no-cache"
        assert response.headers.get("connection") == "close"

        # Parse SSE stream
        chunks = []
        for line in response.iter_lines(decode_unicode=True):
            if line and line.startswith("data: "):
                data_str = line[6:]  # Remove "data: " prefix
                import json

                chunks.append(json.loads(data_str))

        # Should have 3 numbers + 1 completion event
        assert len(chunks) >= 3

    def test_walker_streaming(self) -> None:
        """Test streaming walker with SSE format."""
        response = requests.post(
            f"{self.base_url}/walker/StreamReporter",
            json={"count": 3},
            timeout=30,
            stream=True,
        )

        assert response.status_code == 200
        assert response.headers["content-type"] == "text/event-stream"
        assert response.headers.get("cache-control") == "no-cache"
        assert response.headers.get("connection") == "close"

        # Parse SSE stream
        chunks = []
        for line in response.iter_lines(decode_unicode=True):
            if line and line.startswith("data: "):
                data_str = line[6:]
                import json

                chunks.append(json.loads(data_str))

        # Should have 3 reports + 1 completion event
        assert len(chunks) >= 3

        # Check for reports
        report_items = [c for c in chunks if isinstance(c, str) and "Report" in c]
        assert len(report_items) == 3
