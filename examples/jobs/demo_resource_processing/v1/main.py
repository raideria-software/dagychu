"""Demo Resource Processing: In-memory CPU-intensive computation (quantiles, sorting, aggregations)."""

from __future__ import annotations

import math
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
    samples_count = int(payload.get("samples_count", 20000))

    log(f"Allocating buffer and generating {samples_count:,} Gaussian float samples...")
    t0 = time.monotonic()

    rng = random.Random(1337)
    data = [rng.gauss(100.0, 15.0) for _ in range(samples_count)]

    log("Sorting array and computing statistical percentiles (p50, p90, p99)...")
    data.sort()

    p50 = round(data[int(samples_count * 0.50)], 2)
    p90 = round(data[int(samples_count * 0.90)], 2)
    p99 = round(data[int(samples_count * 0.99)], 2)
    mean = round(sum(data) / samples_count, 2)
    stddev = round(math.sqrt(sum((x - mean) ** 2 for x in data) / samples_count), 2)

    duration_ms = round((time.monotonic() - t0) * 1000, 1)
    log(f"Calculation finished in {duration_ms}ms: mean={mean}, stddev={stddev}, p50={p50}, p90={p90}, p99={p99}")

    write_stdout_json(
        {
            "samples_count": samples_count,
            "mean": mean,
            "stddev": stddev,
            "p50": p50,
            "p90": p90,
            "p99": p99,
            "duration_ms": duration_ms,
            "status": "COMPLETED",
        }
    )


if __name__ == "__main__":
    main()
