"""Demo Unstable Service: Simulates calling a flaky microservice with backoff."""

from __future__ import annotations

import sys
import time

try:
    from jobs._lib.dagychu_stdio import read_stdin_json, write_stdout_json
except ImportError:
    try:
        from _lib.dagychu_stdio import read_stdin_json, write_stdout_json
    except ImportError:
        import json

        def read_stdin_json():
            raw = sys.stdin.read()
            return json.loads(raw) if raw.strip() else {}

        def write_stdout_json(payload):
            sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
            sys.stdout.flush()


def log_info(msg: str) -> None:
    sys.stderr.write(f"[INFO] {msg}\n")
    sys.stderr.flush()


def log_warn(msg: str) -> None:
    sys.stderr.write(f"[WARN] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    endpoint = payload.get("endpoint", "https://api.internal.demo/v2/inventory")
    max_retries = int(payload.get("max_retries", 3))

    log_info(f"Connecting to upstream service endpoint '{endpoint}'...")
    time.sleep(0.04)

    # Simulated microservice responses
    log_warn("Attempt 1/3: HTTP 503 Service Unavailable (rate limit exceeded), backing off 100ms...")
    time.sleep(0.08)

    log_warn("Attempt 2/3: HTTP 503 Service Unavailable (service replica warming up), backing off 200ms...")
    time.sleep(0.08)

    log_info("Attempt 3/3: HTTP 200 OK (payload received: 48 catalog items, latency: 42ms)")
    log_info("Successfully synchronized inventory catalog cache.")

    write_stdout_json(
        {
            "endpoint": endpoint,
            "requests_made": 3,
            "retries": 2,
            "status_code": 200,
            "items_synced": 48,
            "service_latency_ms": 42,
            "status": "SUCCESS",
        }
    )


if __name__ == "__main__":
    main()
