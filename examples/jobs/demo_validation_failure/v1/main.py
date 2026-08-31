"""Demo Validation Failure: Demonstrates business rule violation with clear diagnosis and traceback."""

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


def log_error(msg: str) -> None:
    sys.stderr.write(f"[ERROR] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    allow_invalid = bool(payload.get("allow_invalid", False))

    log_info("Validating incoming financial transaction batch...")
    time.sleep(0.05)

    if not allow_invalid:
        log_error("ValidationError: Record TXN-99201 failed integrity constraint checks:")
        log_error("  - amount: -450.00 (expected positive decimal value > 0)")
        log_error("  - currency: 'XYZ' (not recognized by ISO-4217 standard currency table)")
        log_error("  - merchant_id: '' (mandatory field cannot be blank)")
        log_error("Job aborted: 1 critical validation violation detected in batch.")
        raise ValueError(
            "ValidationFailed: Transaction TXN-99201 contains invalid negative amount (-450.00) and illegal currency 'XYZ'"
        )

    log_info("All 150 transactions passed business validation rules.")
    write_stdout_json(
        {
            "records_checked": 150,
            "violations_found": 0,
            "status": "PASSED",
        }
    )


if __name__ == "__main__":
    main()
