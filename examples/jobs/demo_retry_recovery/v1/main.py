"""Demo Retry Recovery: Simulates transient failure on 1st attempt and automatic recovery on 2nd attempt."""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

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


def log_error(msg: str) -> None:
    sys.stderr.write(f"[ERROR] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    flag_file = Path("/tmp/dagychu_demo_retry_recovery.flag")
    force_success = bool(payload.get("force_success", False))

    log_info("Executing transient service communication step...")
    time.sleep(0.05)

    if not force_success and not flag_file.exists():
        flag_file.write_text("attempt_1_failed", encoding="utf-8")
        log_warn("Connecting to remote payment gateway 'gw.internal.demo:8443'...")
        time.sleep(0.05)
        log_error("ConnectionResetError: Transient connection reset by peer while waiting for ACK")
        log_error("Job attempt #1 failed (Transient error - eligible for Dagychu retry policy)")
        raise ConnectionResetError("Transient network drop during payment gateway handshake")

    # If flag exists or force_success, attempt 2 succeeds and cleans up flag
    if flag_file.exists():
        try:
            flag_file.unlink()
        except OSError:
            pass

    log_info("Retry attempt active: reconnecting with exponential backoff...")
    time.sleep(0.05)
    log_info("Connection established successfully with gateway 'gw.internal.demo:8443'")
    log_info("Transaction batch TXN-84920 processed and confirmed by upstream!")
    log_info("Step recovered successfully on retry attempt.")

    write_stdout_json(
        {
            "recovered": True,
            "gateway_status": "ONLINE",
            "batch_ref": "TXN-84920",
            "status": "SUCCESS",
            "message": "Recovered after transient network drop",
        }
    )


if __name__ == "__main__":
    main()
