"""Demo Timeout: Simulates a long blocking operation to demonstrate worker execution timeout policies."""

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


def log(msg: str) -> None:
    sys.stderr.write(f"[INFO] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    sleep_seconds = float(payload.get("sleep_seconds", 2.0))

    log(f"Starting long operation with requested duration: {sleep_seconds}s...")
    log("If this exceeds the configured job timeout limit, Dagychu worker will terminate the step.")

    elapsed = 0.0
    while elapsed < sleep_seconds:
        chunk = min(1.0, sleep_seconds - elapsed)
        time.sleep(chunk)
        elapsed += chunk
        log(f"Holding execution lock... ({round(elapsed, 1)}s / {sleep_seconds}s)")

    log(f"Job finished without hitting timeout constraint ({elapsed}s total).")
    write_stdout_json(
        {
            "sleep_seconds": sleep_seconds,
            "status": "COMPLETED",
        }
    )


if __name__ == "__main__":
    main()
