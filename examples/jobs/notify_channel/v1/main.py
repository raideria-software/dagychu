from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from html import escape as html_escape
from typing import Any


def _read_input() -> dict[str, Any]:
    raw = sys.stdin.read().strip() or "{}"
    data = json.loads(raw)
    return data if isinstance(data, dict) else {}


def _post_json(url: str, payload: dict[str, Any]) -> None:
    req = urllib.request.Request(
        url=url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as _:
        return


def _post_telegram(url: str, chat_id: str, text: str) -> None:
    _post_json(
        url,
        {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        },
    )


def _should_send(mode: str, statuses: dict[str, str]) -> bool:
    vals = [str(v).upper() for v in statuses.values()]
    has_failed = any(v == "FAILED" for v in vals)
    has_success = any(v == "SUCCEEDED" for v in vals)
    if mode == "always":
        return True
    if mode == "on_any_failure":
        return has_failed
    if mode == "on_all_failure":
        return bool(vals) and all(v == "FAILED" for v in vals)
    if mode == "on_success_only":
        return has_success and not has_failed
    if mode == "on_partial_success":
        return has_success and has_failed
    return True


def _pick_context_value(payload: dict[str, Any], payload_keys: list[str], env_keys: list[str]) -> str:
    for k in payload_keys:
        v = payload.get(k)
        if v is None:
            continue
        s = str(v).strip()
        if s:
            return s
    for k in env_keys:
        s = str(os.getenv(k) or "").strip()
        if s:
            return s
    return ""


def _build_task_link(base_url: str, task_id: str, *, job_name: str = "", job_run_id: str = "") -> str:
    b = str(base_url or "").strip().rstrip("/")
    t = str(task_id or "").strip()
    if not t:
        return ""
    params: dict[str, str] = {"screen": "TASKS", "task_id": t}
    jn = str(job_name or "").strip()
    if jn:
        params["job_name"] = jn
    jrid = str(job_run_id or "").strip()
    if jrid:
        params["job_run_id"] = jrid
    path = f"/?{urllib.parse.urlencode(params)}"
    if not b:
        return path
    return f"{b}{path}"


def _build_message(
    prefix: str,
    statuses: dict[str, str],
    failed: list[str],
    *,
    task_id: str,
    pipeline_group: str,
    pipeline_name: str,
    job_name: str,
    job_run_id: str,
    task_link: str,
) -> str:
    has_failed = bool(failed)
    head_icon = "🚨" if has_failed else "✅"
    title = f"{head_icon} Notify channel report"
    if prefix:
        title = f"{title}\n{prefix}"

    status_lines: list[str] = []
    if statuses:
        for k in sorted(statuses.keys()):
            s = str(statuses[k]).upper()
            icon = "✅" if s == "SUCCEEDED" else "❌" if s == "FAILED" else "⏳"
            status_lines.append(f"{icon} {k}: {s}")

    meta: list[str] = []
    if task_id:
        meta.append(f"Task: {task_id}")
    if pipeline_group or pipeline_name:
        meta.append(f"Pipeline: {pipeline_group}/{pipeline_name}".strip("/"))
    if job_name:
        meta.append(f"Job: {job_name}")
    if job_run_id:
        meta.append(f"Job run: {job_run_id}")
    if task_link:
        meta.append(f"Dagychu task: {task_link}")

    lines: list[str] = [f"<b>{html_escape(title)}</b>"]
    if status_lines:
        lines.append("")
        lines.append("<b>Upstream statuses</b>")
        lines.extend(f"• {html_escape(x)}" for x in status_lines)
    if failed:
        lines.append("")
        lines.append("<b>Failed jobs</b>")
        lines.extend(f"• {html_escape(j)}" for j in failed)
    if meta:
        lines.append("")
        lines.append("<b>Dagychu metadata</b>")
        lines.extend(f"• {html_escape(m)}" for m in meta)
    return "\n".join(lines)[:3900]


def _resolve_runtime_value(payload: dict[str, Any], *, var_field: str, direct_field: str) -> str:
    var_name = str(payload.get(var_field) or "").strip()
    if var_name:
        env_val = str(os.getenv(var_name) or "").strip()
        if env_val:
            return env_val
    return str(payload.get(direct_field) or "").strip()


def main() -> None:
    payload = _read_input()
    mode = str(payload.get("mode") or "always").strip().lower()
    channel = str(payload.get("channel") or "telegram").strip().lower()
    strict = bool(payload.get("strict_delivery") is True)
    statuses = payload.get("upstream_job_statuses")
    status_map = statuses if isinstance(statuses, dict) else {}
    failed_jobs = [k for k, v in status_map.items() if str(v).upper() == "FAILED"]
    task_id = _pick_context_value(payload, ["task_id", "__task_id"], ["DAGYCHU_TASK_ID"])
    pipeline_group = _pick_context_value(
        payload,
        ["pipeline_group", "__pipeline_group"],
        ["DAGYCHU_PIPELINE_GROUP"],
    )
    pipeline_name = _pick_context_value(
        payload,
        ["pipeline_name", "__pipeline_name"],
        ["DAGYCHU_PIPELINE_NAME"],
    )
    job_name = _pick_context_value(payload, ["job_name", "__job_name"], ["DAGYCHU_JOB_NAME"])
    job_run_id = _pick_context_value(
        payload,
        ["job_run_id", "__job_run_id"],
        ["DAGYCHU_JOB_RUN_ID"],
    )
    dagychu_base_url = str(os.getenv("DAGYCHU_PUBLIC_BASE_URL") or "").strip()
    task_link = _build_task_link(
        dagychu_base_url, task_id, job_name=job_name, job_run_id=job_run_id
    )

    should_send = _should_send(mode, status_map)
    delivered = False
    message = _build_message(
        str(payload.get("message_prefix") or ""),
        status_map,
        failed_jobs,
        task_id=task_id,
        pipeline_group=pipeline_group,
        pipeline_name=pipeline_name,
        job_name=job_name,
        job_run_id=job_run_id,
        task_link=task_link,
    )
    error_text: str | None = None
    if should_send:
        try:
            if channel == "telegram":
                token = _resolve_runtime_value(
                    payload,
                    var_field="telegram_bot_token_var",
                    direct_field="telegram_bot_token",
                ) or str(os.getenv("DAGYCHU_TELEGRAM_BOT_TOKEN") or "").strip()
                chat_id = _resolve_runtime_value(
                    payload,
                    var_field="telegram_chat_id_var",
                    direct_field="telegram_chat_id",
                )
                if not token or not chat_id:
                    raise RuntimeError(
                        "telegram credentials are required (telegram_bot_token/telegram_bot_token_var and telegram_chat_id/telegram_chat_id_var)"
                    )
                url = f"https://api.telegram.org/bot{token}/sendMessage"
                _post_telegram(url, chat_id, message)
            elif channel == "slack":
                webhook_url = _resolve_runtime_value(
                    payload,
                    var_field="slack_webhook_url_var",
                    direct_field="slack_webhook_url",
                )
                if not webhook_url:
                    raise RuntimeError("slack_webhook_url is required")
                _post_json(webhook_url, {"text": message})
            else:
                raise RuntimeError(f"Unsupported channel: {channel}")
            delivered = True
        except (urllib.error.URLError, RuntimeError, ValueError) as exc:
            error_text = str(exc)
            if strict:
                raise

    result = {
        "delivered": delivered,
        "mode": mode,
        "channel": channel,
        "failed_jobs": failed_jobs,
        "summary": {"upstream_job_statuses": status_map, "should_send": should_send, "error": error_text},
    }
    sys.stdout.write(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
