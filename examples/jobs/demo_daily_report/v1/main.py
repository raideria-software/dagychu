"""Demo Daily Report: Generates a formatted executive summary report with ASCII dashboard table."""

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
    sys.stderr.write(f"{msg}\n")
    sys.stderr.flush()


def main() -> None:
    payload = read_stdin_json()
    report_date = payload.get("report_date", "2026-08-31")
    total_orders = int(payload.get("total_orders", 1420))
    gross_revenue = float(payload.get("gross_revenue", 84250.00))

    log("Aggregating key performance indicators for daily briefing...")
    time.sleep(0.06)

    table = f"""
============================================================
                 DAILY EXECUTIVE BRIEFING
============================================================
Date: {report_date} | Generated: 09:00:00 UTC
------------------------------------------------------------
Metric                    Value          vs Prev Day
------------------------------------------------------------
Total Orders              {total_orders:,}          +8.4%
Gross Revenue ($)         ${gross_revenue:,.2f}     +12.1%
Average Order Value ($)   $59.33         +3.5%
Conversion Rate           3.42%          +0.21 pp
Active User Sessions      9,812          +5.0%
Top Category              Electronics    (38% of total)
------------------------------------------------------------
Status: EXPORTED TO DASHBOARD & SLACK/TELEGRAM
============================================================
"""
    log(table)

    write_stdout_json(
        {
            "report_date": report_date,
            "total_orders": total_orders,
            "gross_revenue": gross_revenue,
            "aov": 59.33,
            "conversion_rate_pct": 3.42,
            "top_category": "Electronics",
            "status": "PUBLISHED",
        }
    )


if __name__ == "__main__":
    main()
