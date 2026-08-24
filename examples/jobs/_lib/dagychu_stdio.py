"""Bytes-only stdin/stdout for the Dagychu job JSON contract.

``print(json.dumps(...))`` goes through TextIOWrapper and can split a UTF-8
sequence across ~8 KiB chunks. Downstream jobs never read that stream: they
read keys from ``output_json`` after the worker captures **raw bytes**.

Copy this file into your group (``jobs/_lib/dagychu_stdio.py``) or keep it on
``PYTHONPATH`` as ``jobs._lib.dagychu_stdio``.

Logs and ``print`` diagnostics belong on **stderr** (or ``logging`` to stderr)
so they do not mix with the JSON object on stdout.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any

os.environ.setdefault("PYTHONUTF8", "1")


def read_stdin_bytes() -> bytes:
    buf = getattr(sys.stdin, "buffer", None)
    if buf is not None:
        return buf.read()
    return (sys.stdin.read() or "").encode("utf-8")


def read_stdin_json() -> dict[str, Any]:
    raw = read_stdin_bytes()
    if not raw.strip():
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise TypeError(f"stdin JSON must be an object, got {type(data).__name__}")
    return data


def write_stdout_json(payload: Any) -> None:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    if not data.endswith(b"\n"):
        data += b"\n"
    out = getattr(sys.stdout, "buffer", None)
    if out is None:
        sys.stdout.write(data.decode("utf-8"))
        sys.stdout.flush()
        return
    out.write(data)
    out.flush()
