"""Demo Orders Validate: Validates incoming orders schema and value domains."""

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
    sys.stderr.write(f"[INFO] [VALIDATE] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    orders = payload.get("orders") or payload.get("orders_raw") or []

    log(f"Validating batch of {len(orders)} order records...")
    time.sleep(0.05)

    valid_orders = []
    invalid_orders = []

    for order in orders:
        if not order.get("id") or not order.get("user_id"):
            invalid_orders.append(order)
            continue
        if float(order.get("price", 0.0)) <= 0.0 or int(order.get("qty", 0)) <= 0:
            invalid_orders.append(order)
            continue
        valid_orders.append(order)

    log(f"Validation complete: {len(valid_orders)} passed, {len(invalid_orders)} rejected.")

    write_stdout_json(
        {
            "validated_orders": valid_orders,
            "valid_count": len(valid_orders),
            "invalid_count": len(invalid_orders),
            "status": "VALIDATED",
        }
    )


if __name__ == "__main__":
    main()
