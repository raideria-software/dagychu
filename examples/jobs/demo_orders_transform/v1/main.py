"""Demo Orders Transform: Normalizes currencies to USD and computes taxes/discounts."""

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
    sys.stderr.write(f"[INFO] [TRANSFORM] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    orders = payload.get("orders") or payload.get("validated_orders") or []

    log(f"Transforming and enriching {len(orders)} order records...")
    time.sleep(0.05)

    rates_to_usd = {"USD": 1.0, "EUR": 1.08, "RUB": 0.011}
    transformed = []
    total_revenue_usd = 0.0
    total_items = 0

    for order in orders:
        curr = order.get("currency", "USD")
        rate = rates_to_usd.get(curr, 1.0)
        qty = int(order.get("qty", 1))
        price_native = float(order.get("price", 0.0))
        price_usd = round(price_native * rate, 2)
        total_usd = round(price_usd * qty, 2)

        total_revenue_usd += total_usd
        total_items += qty

        transformed.append(
            {
                "id": order.get("id"),
                "user_id": order.get("user_id"),
                "item": order.get("item"),
                "qty": qty,
                "price_usd": price_usd,
                "total_usd": total_usd,
            }
        )

    total_revenue_usd = round(total_revenue_usd, 2)
    log(f"Transformation complete: {len(transformed)} records normalized. Total revenue: ${total_revenue_usd:,.2f}")

    write_stdout_json(
        {
            "transformed_orders": transformed,
            "total_revenue": total_revenue_usd,
            "total_items": total_items,
            "status": "TRANSFORMED",
        }
    )


if __name__ == "__main__":
    main()
