#!/usr/bin/env python3
"""Fill a first-install .env from .env.example: generate secrets and project groups."""

from __future__ import annotations

import argparse
import secrets
import sys
from pathlib import Path
from urllib.parse import quote, urlparse, urlunparse

ALPHANUM = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

PLACEHOLDER_EXACT = frozenset(
    {
        "change_me",
        "change_me_admin_token",
        "change_me_service_token",
        "change_me_clickhouse_admin",
        "change_me_clickhouse_bi",
        "replace-with-long-random-string",
        "guest",
    }
)

TOKEN_KEYS = frozenset(
    {
        "UI_ADMIN_TOKEN",
        "WORKER_SERVICE_TOKEN",
        "EXTERNAL_AGENT_TOKEN",
        "UI_BACKEND_SERVICE_TOKEN",
    }
)

SECRET_KEYS = frozenset(
    {
        "POSTGRES_PASSWORD",
        "RABBITMQ_PASSWORD",
        "PROJECT_VARS_SECRET_KEY",
        "CLICKHOUSE_ADMIN_PASSWORD",
        "CLICKHOUSE_READONLY_PASSWORD",
        *TOKEN_KEYS,
    }
)

USER_PROJECTS = "demo=demo,development=development,production=production"
SYSTEM_GROUP = "dagychu_system=repo:system/dagychu_system"


def random_secret(length: int = 32) -> str:
    return "".join(secrets.choice(ALPHANUM) for _ in range(length))


def parse_assignments(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        key, value = s.split("=", 1)
        key = key.strip()
        if key:
            out[key] = value.strip()
    return out


def is_placeholder(key: str, value: str) -> bool:
    v = value.strip()
    if key in TOKEN_KEYS and not v:
        return True
    if not v:
        return False
    if v in PLACEHOLDER_EXACT:
        if key == "RABBITMQ_PASSWORD" or key == "RABBITMQ_USER":
            return key == "RABBITMQ_PASSWORD" and v == "guest"
        return True
    if v.startswith("change_me"):
        return True
    if "change_me" in v or "replace-with-long-random-string" in v:
        return True
    return False


def _replace_url_password(url: str, user: str, password: str) -> str:
    parsed = urlparse(url)
    host = parsed.hostname or "localhost"
    port = f":{parsed.port}" if parsed.port else ""
    path = parsed.path or ""
    query = f"?{parsed.query}" if parsed.query else ""
    scheme = parsed.scheme or "http"
    safe_user = quote(user, safe="")
    safe_password = quote(password, safe="")
    netloc = f"{safe_user}:{safe_password}@{host}{port}"
    return urlunparse((scheme, netloc, path, "", parsed.query, parsed.fragment))


def resolve_edition(root: Path, explicit: str | None) -> str:
    if explicit:
        return explicit.strip().lower()
    edition_file = root / "EDITION"
    if edition_file.is_file():
        return edition_file.read_text(encoding="utf-8").strip().lower()
    if (root / "system" / "dagychu_system").is_dir():
        return "enterprise"
    return "community"


def set_assignment_lines(lines: list[str], key: str, value: str) -> list[str]:
    updated = False
    out: list[str] = []
    for raw in lines:
        stripped = raw.strip()
        if stripped and not stripped.startswith("#") and "=" in raw:
            k = raw.split("=", 1)[0].strip()
            if k == key:
                out.append(f"{key}={value}")
                updated = True
                continue
        out.append(raw)
    if not updated:
        out.append(f"{key}={value}")
    return out


def generate_env_file(
    env_path: Path,
    *,
    root: Path,
    edition: str | None = None,
) -> dict[str, str]:
    text = env_path.read_text(encoding="utf-8")
    lines = text.splitlines()
    current = parse_assignments(text)
    resolved = resolve_edition(root, edition)

    secrets_map: dict[str, str] = {}
    for key in SECRET_KEYS:
        raw = current.get(key, "")
        if is_placeholder(key, raw) or key not in current:
            secrets_map[key] = random_secret(32)
        else:
            secrets_map[key] = raw.strip()

    pg_user = current.get("POSTGRES_USER", "app_user").strip() or "app_user"
    pg_password = secrets_map["POSTGRES_PASSWORD"]
    db_url = current.get("DATABASE_URL", "").strip()
    if not db_url or is_placeholder("DATABASE_URL", db_url):
        db_name = current.get("POSTGRES_DB", "dagychu").strip() or "dagychu"
        db_url = f"postgresql+psycopg://{pg_user}:{pg_password}@postgres:5432/{db_name}"
    else:
        db_url = _replace_url_password(db_url, pg_user, pg_password)

    # Docker RabbitMQ rejects AMQP for the built-in "guest" user from other containers
    # (loopback_users). A non-guest broker user is required for a healthy first install.
    rmq_user = (current.get("RABBITMQ_USER") or "").strip() or "dagychu"
    if rmq_user.lower() == "guest":
        rmq_user = "dagychu"
    rmq_password = secrets_map["RABBITMQ_PASSWORD"]
    rmq_url = (
        f"amqp://{quote(rmq_user, safe='')}:{quote(rmq_password, safe='')}@rabbitmq:5672/"
    )

    pipeline_dirs = USER_PROJECTS
    if resolved != "community":
        pipeline_dirs = f"{USER_PROJECTS},{SYSTEM_GROUP}"
    job_executor = "docker"

    queue_name = (current.get("QUEUE_NAME") or "task_queue").strip() or "task_queue"

    assignments = {
        **{k: secrets_map[k] for k in SECRET_KEYS},
        "DATABASE_URL": db_url,
        "RABBITMQ_USER": rmq_user,
        "RABBITMQ_URL": rmq_url,
        "QUEUE_NAME": queue_name,
        "PIPELINE_YAML_DIRS": pipeline_dirs,
        "JOB_EXECUTOR": job_executor,
    }
    if resolved == "community":
        assignments["CLICKHOUSE_URL"] = ""

    for key, value in assignments.items():
        lines = set_assignment_lines(lines, key, value)

    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return assignments


def merge_missing_keys(example_path: Path, env_path: Path) -> list[str]:
    """Append keys present in example but missing from env. Does not overwrite."""
    example_text = example_path.read_text(encoding="utf-8")
    env_text = env_path.read_text(encoding="utf-8")
    example_vals = parse_assignments(example_text)
    env_vals = parse_assignments(env_text)
    missing = [k for k in example_vals if k not in env_vals]
    if not missing:
        return []
    extra = [f"{k}={example_vals[k]}" for k in missing]
    env_path.write_text(env_text.rstrip("\n") + "\n" + "\n".join(extra) + "\n", encoding="utf-8")
    return missing


def ensure_system_pipeline_group(env_path: Path, *, has_system: bool) -> bool:
    if not has_system:
        return False
    text = env_path.read_text(encoding="utf-8")
    vals = parse_assignments(text)
    current = vals.get("PIPELINE_YAML_DIRS", "")
    if "dagychu_system" in current:
        return False
    new_val = f"{current},{SYSTEM_GROUP}" if current.strip() else SYSTEM_GROUP
    lines = set_assignment_lines(text.splitlines(), "PIPELINE_YAML_DIRS", new_val)
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--edition", default=None)
    parser.add_argument(
        "--merge-missing",
        action="store_true",
        help="Append keys from --example that are missing in --env (no secret regen).",
    )
    parser.add_argument("--example", type=Path, default=None)
    args = parser.parse_args(argv)

    env_path = args.env
    root = args.root or env_path.parent
    if args.merge_missing:
        if args.example is None:
            print("--example is required with --merge-missing", file=sys.stderr)
            return 2
        added = merge_missing_keys(args.example, env_path)
        edition = resolve_edition(root, args.edition)
        if edition != "community":
            ensure_system_pipeline_group(env_path, has_system=True)
        if added:
            print("appended missing keys: " + ", ".join(added))
        else:
            print("no missing keys")
        return 0

    generate_env_file(env_path, root=root, edition=args.edition)
    print(f"generated secrets and project groups in {env_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
