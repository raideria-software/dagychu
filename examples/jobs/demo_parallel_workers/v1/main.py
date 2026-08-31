"""Demo Parallel Workers: Simulates processing an independent shard/partition."""

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
    worker_id = payload.get("worker_id", "worker-01")
    partition_id = int(payload.get("partition_id", 1))
    records_count = int(payload.get("records_count", 250))

    log(f"[{worker_id}] Assigned to process partition #{partition_id} ({records_count} records)...")
    time.sleep(0.08)
    log(f"[{worker_id}] Computed partition checksum: crc32=84F9B10{partition_id}")
    log(f"[{worker_id}] Partition #{partition_id} processed successfully.")

    write_stdout_json(
        {
            "worker_id": worker_id,
            "partition_id": partition_id,
            "records_processed": records_count,
            "status": "COMPLETED",
        }
    )


if __name__ == "__main__":
    main()
