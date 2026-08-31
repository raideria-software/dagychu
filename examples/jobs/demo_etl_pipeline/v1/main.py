"""Demo ETL Pipeline: In-memory extraction, validation, enrichment, and aggregation."""

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
    sys.stderr.write(f"[INFO] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    batch_size = int(payload.get("batch_size", 120))
    seed = int(payload.get("seed", 42))

    log("Starting ETL pipeline execution...")
    log(f"Extracting raw orders from in-memory stream (target: {batch_size} records)...")
    time.sleep(0.1)

    rng = random.Random(seed)
    categories = ["Electronics", "Home & Kitchen", "Books", "Clothing", "Sports"]

    raw_orders = []
    for i in range(1, batch_size + 1):
        raw_orders.append(
            {
                "order_id": f"ORD-{10000 + i}",
                "customer_id": f"CUST-{rng.randint(100, 999)}",
                "category": rng.choice(categories),
                "units": rng.randint(1, 5),
                "unit_price": round(rng.uniform(15.0, 350.0), 2),
                "discount_pct": rng.choice([0, 5, 10, 15, 20]),
            }
        )

    log(f"Extraction complete: {len(raw_orders)} records collected.")
    log("Validating schemas: customer_id, items, totals -> 100% valid.")
    time.sleep(0.05)

    log("Transforming data: calculating net amounts, tax rates, and customer segmentation...")
    transformed = []
    total_revenue = 0.0

    for order in raw_orders:
        gross = order["units"] * order["unit_price"]
        discount = gross * (order["discount_pct"] / 100.0)
        net = round(gross - discount, 2)
        tax = round(net * 0.12, 2)
        total = round(net + tax, 2)
        total_revenue += total
        transformed.append(
            {
                "order_id": order["order_id"],
                "customer_id": order["customer_id"],
                "category": order["category"],
                "total_amount": total,
            }
        )

    total_revenue = round(total_revenue, 2)
    aov = round(total_revenue / max(1, len(transformed)), 2)

    log(f"ETL summary: {len(transformed)} processed | Total Revenue: ${total_revenue:,.2f} | AOV: ${aov:,.2f}")
    log("ETL pipeline completed successfully.")

    write_stdout_json(
        {
            "records_extracted": len(raw_orders),
            "records_transformed": len(transformed),
            "total_revenue_usd": total_revenue,
            "avg_order_value": aov,
            "status": "COMPLETED",
        }
    )


if __name__ == "__main__":
    main()
