"""Demo Orders Extract: Extracts raw orders from in-memory stream for the guided demo workflow."""

from __future__ import annotations

import random
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
    sys.stderr.write(f"[INFO] [EXTRACT] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    order_date = payload.get("date", "2026-08-31")
    count = int(payload.get("count", 50))
    seed = int(payload.get("seed", 101))

    log(f"Extracting source orders for date '{order_date}' (target batch: {count} records)...")
    time.sleep(0.06)

    rng = random.Random(seed)
    items = ["Smart Keyboard", "Wireless Mouse", "USB-C Hub", "4K Monitor", "Noise Cancelling Headphones"]
    currencies = ["USD", "EUR", "RUB"]

    orders = []
    for i in range(1, count + 1):
        orders.append(
            {
                "id": f"ORD-{20000 + i}",
                "user_id": f"USR-{rng.randint(1000, 9999)}",
                "item": rng.choice(items),
                "qty": rng.randint(1, 4),
                "price": round(rng.uniform(25.0, 399.0), 2),
                "currency": rng.choice(currencies),
                "date": order_date,
            }
        )

    log(f"Extracted {len(orders)} raw order records from upstream source.")
    write_stdout_json(
        {
            "orders_raw": orders,
            "count": len(orders),
            "date": order_date,
            "status": "EXTRACTED",
        }
    )


if __name__ == "__main__":
    main()
