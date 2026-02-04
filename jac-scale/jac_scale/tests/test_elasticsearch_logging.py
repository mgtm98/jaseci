"""Test Elasticsearch logging integration with Jac Scale.

This test verifies that the ElasticsearchLogger in jac-scale properly:
- Connects to Elasticsearch
- Logs operations from Jac applications
- Stores logs in the correct indices
- Handles different log levels and contexts
"""

import contextlib
import gc
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from elasticsearch import Elasticsearch
from testcontainers.elasticsearch import ElasticSearchContainer


def get_free_port() -> int:
    """Get a free port for the Jac server."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestElasticsearchLogging:
    """Test Elasticsearch logging integration with Jac Scale.

    This test verifies that the ElasticsearchLogger in jac-scale:
    - Connects to Elasticsearch from Jac applications
    - Logs operations with proper structure
    - Saves logs in Elasticsearch indices
    """

    fixtures_dir: Path
    logger_jac_file: Path
    es_toml_file: Path

    es_client: Elasticsearch  # For verification only
    es_container: ElasticSearchContainer

    @classmethod
    def setup_class(cls) -> None:
        """Set up test environment with Elasticsearch container."""
        cls.fixtures_dir = Path(__file__).parent / "fixtures"
        cls.logger_jac_file = (
            cls.fixtures_dir / "elastic_search" / "logger_test_app.jac"
        )
        cls.es_toml_file = cls.fixtures_dir / "elastic_search" / "jac.toml"

        if not cls.logger_jac_file.exists():
            raise FileNotFoundError(f"Missing Jac file: {cls.logger_jac_file}")

        # Clean up session file from previous runs
        session_file = (
            cls.fixtures_dir / ".jac" / "data" / "todo_app.session.users.json"
        )
        if session_file.exists():
            os.remove(session_file)

        # Start Elasticsearch container with security disabled for testing
        # Using 7.x for simpler setup (no security by default)
        cls.es_container = (
            ElasticSearchContainer(
                "docker.elastic.co/elasticsearch/elasticsearch:7.17.10"
            )
            .with_env("discovery.type", "single-node")
            .with_env("xpack.security.enabled", "false")
        )
        cls.es_container.start()

        es_host = cls.es_container.get_container_host_ip()
        es_port = cls.es_container.get_exposed_port(9200)
        es_url = f"http://{es_host}:{es_port}"

        # Create Elasticsearch client for verification
        cls.es_client = Elasticsearch([es_url])

        # Wait for Elasticsearch to be ready (can take 30-60 seconds)
        max_retries = 60
        print(f"⏳ Waiting for Elasticsearch to start at {es_url}...")
        for i in range(max_retries):
            try:
                if cls.es_client.ping():
                    print(f"✅ Elasticsearch is ready after {i + 1} attempts")
                    break
            except Exception as e:
                if i == max_retries - 1:
                    raise RuntimeError(
                        f"Elasticsearch failed to start after {max_retries} seconds.\n"
                        f"URL: {es_url}\n"
                        f"Last error: {e}\n"
                        f"Container logs: {cls.es_container.get_logs()}"
                    )
                if i % 10 == 0:  # Print progress every 10 seconds
                    print(f"  Still waiting... ({i + 1}/{max_retries})")
                time.sleep(1)

        # Create TOML configuration file with dynamic ES URL
        toml_content = f"""[plugins.scale.logging]
type = "elasticsearch"

[plugins.scale.logging.elasticsearch]
enabled = true
hosts = "{es_url}"
bulk_size = 10
"""
        print(f"📝 Creating jac.toml at: {cls.es_toml_file}")
        cls.es_toml_file.write_text(toml_content)
        print(f"✅ jac.toml created successfully")
        print(f"📋 TOML content:\n{toml_content}")

        # Set environment variables (backup approach if TOML doesn't work)
        os.environ["JAC_SCALE_LOGGING_TYPE"] = "elasticsearch"
        os.environ["JAC_SCALE_LOGGING_ES_ENABLED"] = "true"
        os.environ["JAC_SCALE_LOGGING_ES_HOSTS"] = es_url
        os.environ["JAC_SCALE_LOGGING_ES_BULK_SIZE"] = "10"

    @classmethod
    def teardown_class(cls) -> None:
        """Clean up test environment."""
        # Clean up Elasticsearch indices
        if cls.es_client:
            with contextlib.suppress(Exception):
                cls.es_client.indices.delete(index="jac-*")
            with contextlib.suppress(Exception):
                cls.es_client.close()

        if cls.es_container:
            cls.es_container.stop()

        # Clean up environment variables
        for key in [
            "JAC_SCALE_LOGGING_TYPE",
            "JAC_SCALE_LOGGING_ES_ENABLED",
            "JAC_SCALE_LOGGING_ES_HOSTS",
            "JAC_SCALE_LOGGING_ES_BULK_SIZE",
        ]:
            os.environ.pop(key, None)

        time.sleep(0.5)
        gc.collect()

        # Clean up TOML configuration file
        if cls.es_toml_file and cls.es_toml_file.exists():
            os.remove(cls.es_toml_file)
            print(f"🧹 Cleaned up jac.toml: {cls.es_toml_file}")

        # Clean up session file (if any was created)
        session_file = (
            cls.fixtures_dir / ".jac" / "data" / "logger_test_app.session.users.json"
        )
        if session_file.exists():
            os.remove(session_file)

    @classmethod
    def _run_jac_app(cls, jac_file: Path) -> tuple[str, str]:
        """Run a Jac application directly and return stdout/stderr."""
        jac_executable = Path(sys.executable).parent / "jac"
        # Use absolute path to the jac file
        cmd = [str(jac_executable), "run", str(jac_file.absolute())]

        env = os.environ.copy()

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=str(jac_file.parent),  # Run from the directory containing the jac file
            env=env,
            timeout=30,
        )

        return result.stdout, result.stderr

    def _wait_for_es_indexing(self, seconds: float = 2.0) -> None:
        """Wait for Elasticsearch to index documents and refresh indices."""
        time.sleep(seconds)
        with contextlib.suppress(Exception):
            # If index doesn't exist yet, that's ok
            self.es_client.indices.refresh(index="jac-*")

    def _search_es_logs(
        self, query: dict[str, Any], size: int = 100
    ) -> list[dict[str, Any]]:
        """Search Elasticsearch logs and return hits."""
        try:
            search_result = self.es_client.search(
                index="jac-*",
                body={"query": query, "size": size, "sort": [{"@timestamp": "desc"}]},
            )
            return [hit["_source"] for hit in search_result["hits"]["hits"]]
        except Exception:
            # Index might not exist yet
            return []

    def test_jac_logger_to_elasticsearch(self) -> None:
        """Test that Jac logger connects to Elasticsearch and saves logs.

        This test:
        1. Runs a Jac application that uses UtilityFactory.create_configured_logger()
        2. The Jac app logs multiple events with different levels
        3. Verifies that logs are actually saved in Elasticsearch
        4. Validates log structure and content
        """
        # Verify Elasticsearch is accessible
        print("\n🔍 Checking Elasticsearch connection...")
        try:
            is_accessible = self.es_client.ping()
            if is_accessible:
                print("✅ Elasticsearch is accessible")
            else:
                print("❌ Elasticsearch ping returned False")
        except Exception as e:
            print(f"❌ Elasticsearch ping failed with error: {e}")
            is_accessible = False

        assert is_accessible, (
            f"Elasticsearch should be accessible before test\n"
            f"ES URL: {os.environ.get('JAC_SCALE_LOGGING_ES_HOSTS')}\n"
            f"Try: docker ps (to check if container is running)\n"
            f"Try: sudo usermod -aG docker $USER && newgrp docker (for permissions)"
        )

        # Run the logger test application
        print("\n🔄 Running Jac logger test application...")
        stdout, stderr = self._run_jac_app(self.logger_jac_file)

        print(f"📋 STDOUT:\n{stdout}")
        if stderr:
            print(f"⚠️  STDERR:\n{stderr}")

        # Check for execution errors (but allow warnings)
        critical_errors = ["Error:", "Exception:", "Traceback"]
        has_critical_error = any(err in stderr for err in critical_errors)

        assert not has_critical_error, (
            f"Jac app execution failed with critical error:\nSTDOUT: {stdout}\nSTDERR: {stderr}"
        )

        # Wait for Elasticsearch to index the logs
        print("⏳ Waiting for Elasticsearch to index logs...")
        self._wait_for_es_indexing(3.0)

        # Search for ANY logs in Elasticsearch (broad search first)
        print("🔍 Searching for logs in Elasticsearch...")
        all_logs = self._search_es_logs({"match_all": {}}, size=100)

        print(f"📊 Found {len(all_logs)} total logs in Elasticsearch")

        assert len(all_logs) > 0, (
            f"No logs found in Elasticsearch after running Jac app!\n"
            f"STDOUT: {stdout}\n"
            f"STDERR: {stderr}\n"
            f"ES URL: {os.environ.get('JAC_SCALE_LOGGING_ES_HOSTS')}"
        )

        # Search for logs from our specific test app
        test_logs = self._search_es_logs(
            {
                "bool": {
                    "should": [
                        {"match": {"event": "app_start"}},
                        {"match": {"event": "test_info"}},
                        {"match": {"event": "test_warning"}},
                        {"match": {"event": "test_error"}},
                        {"match": {"event": "bulk_test"}},
                        {"match": {"test_id": "es_test_001"}},
                        {"match": {"walker": "LogTestWalker"}},
                    ],
                    "minimum_should_match": 1,
                }
            },
            size=50,
        )

        print(f"✅ Found {len(test_logs)} logs from logger test app")

        # Print sample logs for debugging
        if test_logs:
            print(f"📄 Sample log entry: {test_logs[0]}")

        assert len(test_logs) > 0, (
            f"No logs from logger test app found in Elasticsearch!\n"
            f"Expected events: app_start, test_info, test_warning, test_error, bulk_test\n"
            f"Total logs in ES: {len(all_logs)}\n"
            f"Sample of all logs: {all_logs[:3] if all_logs else 'None'}"
        )

        # Verify log structure
        print("🔬 Validating log structure...")
        for i, log in enumerate(test_logs[:5]):  # Check first 5 logs
            # Check for timestamp
            has_timestamp = "@timestamp" in log or "timestamp" in log
            assert has_timestamp, f"Log #{i} missing timestamp field: {log}"

            # Check for content (event or message)
            has_content = "event" in log or "message" in log or "msg" in log
            assert has_content, f"Log #{i} missing event/message field: {log}"

        # Verify specific events were logged
        events = [log.get("event") for log in test_logs if "event" in log]
        print(f"📋 Logged events: {set(events)}")

        # We should have at least the app_start event or multiple log entries
        assert "app_start" in events or len(test_logs) >= 5, (
            f"Expected 'app_start' event or at least 5 log entries.\n"
            f"Found events: {events}\n"
            f"Total test logs: {len(test_logs)}"
        )

        print(
            f"✅ Test passed! Successfully verified {len(test_logs)} logs in Elasticsearch"
        )
