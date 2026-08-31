"""Demo API Sync: Simulates paginated API sync with rate-limit respect."""

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
    total_pages = int(payload.get("total_pages", 5))
    items_per_page = int(payload.get("items_per_page", 25))

    log(f"Starting paginated API synchronization ({total_pages} pages, {items_per_page} items/page)...")

    total_records = 0
    for page in range(1, total_pages + 1):
        log(f"Fetching [Page {page}/{total_pages}] from API gateway (offset={total_records})...")
        time.sleep(0.05)
        total_records += items_per_page
        log(f"-> Received {items_per_page} items (Rate limit remaining: {100 - page * 5}/100 tokens)")

    log(f"API sync completed: {total_records} records fetched across {total_pages} pages.")

    write_stdout_json(
        {
            "pages_fetched": total_pages,
            "total_records": total_records,
            "status": "COMPLETED",
        }
    )


if __name__ == "__main__":
    main()
