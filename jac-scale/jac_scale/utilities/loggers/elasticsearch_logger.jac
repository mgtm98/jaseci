"""Elasticsearch logger implementation for centralized logging.

Sends log messages to Elasticsearch for aggregation, search, and analysis.
Includes context enrichment (pod_name, namespace, service_name, timestamp).
Supports bulk writes for efficiency. Gracefully falls back to console on failure.
"""
import from typing { Any }
import from jac_scale.abstractions.logger { Logger }
import from jaclang.cli.console { console }
import from datetime { datetime }
import os;

"""Elasticsearch logger with bulk writes and graceful fallback."""
class ElasticsearchLogger(Logger) {
    has client: object | None = None,
        index_prefix: str = "jac-scale",
        bulk_size: int = 100,
        bulk_buffer: list[dict[str, Any]] = [],
        pod_name: str = "",
        namespace: str = "",
        service_name: str = "",
        fallback_mode: bool = False;

    """Initialize Elasticsearch connection."""
    def init(self: ElasticsearchLogger, config: dict[str, Any] = {}) -> None {
        self.index_prefix = config.get("index_prefix", "jac-scale");
        self.bulk_size = config.get("bulk_size", 100);
        self.pod_name = os.getenv("HOSTNAME", "unknown-pod");
        self.namespace = os.getenv("NAMESPACE", "default");
        self.service_name = os.getenv("SERVICE_NAME", "jac-scale");

        # Initialize Elasticsearch client
        if config.get("enabled", False) {
            try {
                import from elasticsearch { Elasticsearch }

                hosts = config.get("hosts", "localhost:9200");
                username = config.get("username", "");
                password = config.get("password", "");
                api_key = config.get("api_key", "");

                # Parse hosts (can be comma-separated string or list)
                if isinstance(hosts, str) {
                    hosts = [h.strip() for h in hosts.split(',')];
                }

                # Configure authentication (API key takes precedence)
                if api_key {
                    self.client = Elasticsearch(hosts=hosts, api_key=api_key);
                } elif username and password {
                    self.client = Elasticsearch(
                        hosts=hosts, basic_auth=(username, password)
                    );
                } else {
                    self.client = Elasticsearch(hosts=hosts);
                }

                # Test connection
                if self.client.ping() {
                    auth_method = "API key"
                    if api_key
                    else ("basic auth" if username else "no auth");
                    console.info(
                        f"[ElasticsearchLogger] Connected to Elasticsearch at {hosts} using {auth_method}"
                    );
                } else {
                    console.warning(
                        "[ElasticsearchLogger] Failed to ping Elasticsearch, falling back to console"
                    );
                    self.fallback_mode = True;
                }
            } except Exception as e {
                console.warning(
                    f"[ElasticsearchLogger] Failed to initialize: {e}. Falling back to console"
                );
                self.fallback_mode = True;
            }
        } else {
            console.info(
                "[ElasticsearchLogger] Elasticsearch disabled in config, using console fallback"
            );
            self.fallback_mode = True;
        }
    }

    """Enrich log entry with metadata."""
    def _enrich_context(self: ElasticsearchLogger, message: str, level: str, context: dict[str, Any]) -> dict[str, Any] {
        log_entry = {
            "@timestamp": datetime.utcnow().isoformat(),
            "level": level,
            "message": message,
            "pod_name": self.pod_name,
            "namespace": self.namespace,
            "service_name": self.service_name
        };
        log_entry.update(context);
        return log_entry;
    }

    """Add log entry to bulk buffer and flush if needed."""
    def _send_log(self: ElasticsearchLogger, log_entry: dict[str, Any]) -> None {
        if self.fallback_mode {
            # Fallback to console
            level = log_entry.get("level", "INFO");
            message = log_entry.get("message", "");
            context = log_entry.get("context", {});
            if level == "ERROR" {
                if context {
                    console.error(f"{message} | Context: {context}");
                } else {
                    console.error(message);
                }
            } elif level == "WARN" {
                if context {
                    console.warning(f"{message} | Context: {context}");
                } else {
                    console.warning(message);
                }
            } elif level == "DEBUG" {
                if context {
                    console.print(
                        f"[DEBUG] {message} | Context: {context}", style="muted"
                    );
                } else {
                    console.print(f"[DEBUG] {message}", style="muted");
                }
            } else {
                if context {
                    console.info(f"{message} | Context: {context}");
                } else {
                    console.info(message);
                }
            }
            return;
        }

        # Add to bulk buffer
        self.bulk_buffer.append(log_entry);

        # Flush if buffer is full
        if len(self.bulk_buffer) >= self.bulk_size {
            self._flush();
        }
    }

    """Flush bulk buffer to Elasticsearch."""
    def _flush(self: ElasticsearchLogger) -> None {
        if not self.bulk_buffer or self.fallback_mode or not self.client {
            return;
        }

        try {
            import from elasticsearch.helpers { bulk }

            # Prepare actions for bulk insert
            actions = [
                {
                    "_index": f"{self.index_prefix}-{datetime.utcnow():%Y.%m.%d}",
                    "_source": log
                } for log in self.bulk_buffer
            ];

            (success_count, failed_items) = bulk(self.client, actions, raise_on_error=False);
            failed_count = len(failed_items) if isinstance(failed_items, list) else 0;
            if failed_count > 0 {
                console.warning(f"[ElasticsearchLogger] Failed to index {failed_count} log entries");
            }
            self.bulk_buffer = [];
        } except Exception as e {
            console.error(f"[ElasticsearchLogger] Failed to flush logs: {e}");
            # Switch to fallback mode on persistent errors
            self.fallback_mode = True;
        }
    }

    """Log an info message."""
    def info(
        self: ElasticsearchLogger, message: str, context: dict[str, Any] = {}
    ) -> None {
        log_entry = self._enrich_context(message, "INFO", context);
        self._send_log(log_entry);
    }

    """Log an error message."""
    def error(
        self: ElasticsearchLogger, message: str, context: dict[str, Any] = {}
    ) -> None {
        log_entry = self._enrich_context(message, "ERROR", context);
        self._send_log(log_entry);
    }

    """Log a warning message."""
    def warn(
        self: ElasticsearchLogger, message: str, context: dict[str, Any] = {}
    ) -> None {
        log_entry = self._enrich_context(message, "WARN", context);
        self._send_log(log_entry);
    }

    """Log a debug message."""
    def debug(
        self: ElasticsearchLogger, message: str, context: dict[str, Any] = {}
    ) -> None {
        log_entry = self._enrich_context(message, "DEBUG", context);
        self._send_log(log_entry);
    }

    """Flush remaining logs and close connection."""
    def close(self: ElasticsearchLogger) -> None {
        self._flush();
        if self.client {
            try {
                self.client.close();
            } except Exception as e {
                console.error(f"[ElasticsearchLogger] Failed to close client: {e}");
            }
        }
    }
}
