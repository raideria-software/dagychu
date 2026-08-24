from __future__ import annotations

import json
import sys
from datetime import datetime, timezone


def main() -> int:
    payload = json.loads(sys.stdin.read() or "{}")
    minute = datetime.now(tz=timezone.utc).minute
    if minute % 2 == 0:
        raise RuntimeError(f"Intentional demo failure on even UTC minute={minute}")
    out = {
        "ok": True,
        "minute_utc": minute,
        "note": "Succeeded on odd minute",
        "echo": payload,
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
