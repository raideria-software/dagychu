"""Demo Orders Report: Final aggregation and reporting stage of demo_orders_workflow."""

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
    sys.stderr.write(f"[INFO] [REPORT] {msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    orders = payload.get("orders") or payload.get("transformed_orders") or []
    total_revenue = float(payload.get("total_revenue", 0.0))
    if not total_revenue and orders:
        total_revenue = sum(float(o.get("total_usd", 0.0)) for o in orders)

    log(f"Generating final orders summary report for {len(orders)} transformed orders...")
    time.sleep(0.05)

    log("------------------------------------------------------------")
    log(f"  ORDERS WORKFLOW SUMMARY REPORT")
    log(f"  Orders Processed : {len(orders)}")
    log(f"  Gross Revenue    : ${total_revenue:,.2f}")
    if orders:
        avg = round(total_revenue / len(orders), 2)
        log(f"  Avg Basket Size  : ${avg:,.2f}")
    log("  Workflow Status  : SUCCESSFUL")
    log("------------------------------------------------------------")

    write_stdout_json(
        {
            "report_status": "READY",
            "orders_processed": len(orders),
            "total_revenue": round(total_revenue, 2),
            "status": "COMPLETED",
        }
    )


if __name__ == "__main__":
    main()
