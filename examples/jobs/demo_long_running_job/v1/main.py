"""Demo Long Running Job: Multi-stage pipeline execution demonstrating live progress updates."""

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
    stages = [
        ("Stage 1/6 [16%]", "Initializing compute environment & loading embedding models..."),
        ("Stage 2/6 [33%]", "Ingesting document partitions from storage (1,250 docs)..."),
        ("Stage 3/6 [50%]", "Computing multi-dimensional vector embeddings..."),
        ("Stage 4/6 [66%]", "Building HNSW approximate nearest neighbor index..."),
        ("Stage 5/6 [83%]", "Applying safety, compliance, and PII anonymization filters..."),
        ("Stage 6/6 [100%]", "Serializing and publishing vector index to cache cluster..."),
    ]

    start_time = time.monotonic()
    delay = float(payload.get("stage_delay_sec", 0.3))

    log(f"Starting long running job with {len(stages)} pipeline stages (stage_delay={delay}s)...")

    for prefix, desc in stages:
        log(f"{prefix}: {desc}")
        time.sleep(delay)

    duration = round(time.monotonic() - start_time, 2)
    log(f"Long running job finished successfully in {duration}s.")

    write_stdout_json(
        {
            "stages_completed": len(stages),
            "total_stages": len(stages),
            "total_duration_sec": duration,
            "status": "SUCCESS",
        }
    )


if __name__ == "__main__":
    main()
