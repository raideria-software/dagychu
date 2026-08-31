"""Demo Batch Processing: Processing 500 items in micro-batches with progress tracking."""

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
    total_items = int(payload.get("total_items", 500))
    batch_size = int(payload.get("batch_size", 50))

    num_batches = (total_items + batch_size - 1) // batch_size
    log(f"Initializing batch processor: total_items={total_items}, batch_size={batch_size}, total_batches={num_batches}")

    start_time = time.monotonic()
    processed_count = 0

    for b in range(1, num_batches + 1):
        batch_start = (b - 1) * batch_size + 1
        batch_end = min(b * batch_size, total_items)
        count = batch_end - batch_start + 1
        processed_count += count

        # Simulate batch work
        time.sleep(0.04)
        pct = int((processed_count / total_items) * 100)
        log(f"[Batch {b:2d}/{num_batches:2d}] Processed records {batch_start:4d}..{batch_end:4d} ({count} items) -> Progress: {pct}%")

    duration = round(time.monotonic() - start_time, 2)
    log(f"Batch processing complete: {processed_count} items processed in {duration}s across {num_batches} batches.")

    write_stdout_json(
        {
            "total_processed": processed_count,
            "batches": num_batches,
            "batch_size": batch_size,
            "duration_seconds": duration,
            "status": "SUCCESS",
        }
    )


if __name__ == "__main__":
    main()
