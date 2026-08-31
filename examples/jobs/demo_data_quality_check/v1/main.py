"""Demo Data Quality Check: Validates schema, nullability, formats, duplicates, and calculates score."""

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
    dataset_name = payload.get("dataset_name", "customer_profiles")
    rows_count = int(payload.get("rows_count", 250))

    log_info(f"Starting Data Quality Assessment on dataset '{dataset_name}' ({rows_count} rows)...")
    time.sleep(0.05)

    checks = [
        ("Rule 1/6: Checking non-null primary keys (customer_id)", "PASSED (0 nulls found)"),
        ("Rule 2/6: Checking unique email constraint", "PASSED (0 duplicates detected)"),
        ("Rule 3/6: Checking RFC-5322 email formatting regex", f"PASSED ({rows_count}/{rows_count} valid)"),
        ("Rule 4/6: Validating ISO-8601 registration date boundaries", "PASSED (all dates in [2020..2026])"),
        ("Rule 5/6: Outlier detection on account age & activity score", "PASSED (all z-scores < 3.0)"),
    ]

    for rule, result in checks:
        log_info(f"{rule}... {result}")
        time.sleep(0.03)

    log_warn("Rule 6/6: Optional field 'postal_code' is null in 2 rows (acceptable threshold: < 5%)")

    total_checks = rows_count * 6
    failed_checks = 2
    passed_checks = total_checks - failed_checks
    quality_score = round((passed_checks / total_checks) * 100, 2)

    log_info(f"Data Quality Score: {quality_score}% (Grade: A+) - Dataset Approved for Production.")

    write_stdout_json(
        {
            "dataset": dataset_name,
            "rows_checked": rows_count,
            "passed_checks": passed_checks,
            "failed_checks": failed_checks,
            "quality_score_pct": quality_score,
            "issues": [{"field": "postal_code", "issue": "null_value", "count": 2}],
            "status": "PASSED",
        }
    )


if __name__ == "__main__":
    main()
