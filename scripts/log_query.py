#!/usr/bin/env python3
"""medcare-data-qa audit logger.

Appends one JSON line per Q&A to:
    ~/.lark-dispatcher/logs/medcare-queries.jsonl

Usage (preferred): pipe a JSON object on stdin.
    echo '{"user_id":"ou_xxx","chat_id":"oc_xxx","sql":"SELECT ...","row_count":12,"latency_ms":842,"error":null,"metric":"gmv","filters":{...},"template":"gmv_daily.sql","question":"上周GMV"}' \
        | python3 log_query.py

Usage (flags): supply fields via CLI flags. Use --sql-stdin if SQL contains
specials and you want only SQL on stdin.

Fields (all optional except timestamp which is auto-filled):
    user_id       Lark open_id of the asker
    chat_id       Lark chat_id (group)
    question      Original user question
    metric        Standard metric name resolved
    filters       Filter dict (any JSON value)
    template      SQL template filename used
    sql           Final executed SQL (auto-truncated to 2000 chars)
    row_count     Rows returned
    latency_ms    End-to-end query latency in ms
    error         Error message string, or null on success
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

LOG_PATH = Path.home() / ".lark-dispatcher" / "logs" / "medcare-queries.jsonl"
SQL_MAX = 2000


def truncate_sql(sql: str | None) -> str | None:
    if sql is None:
        return None
    if len(sql) <= SQL_MAX:
        return sql
    return sql[:SQL_MAX] + f"...[truncated {len(sql) - SQL_MAX} chars]"


def build_record(data: dict) -> dict:
    return {
        "ts": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "user_id": data.get("user_id"),
        "chat_id": data.get("chat_id"),
        "question": data.get("question"),
        "metric": data.get("metric"),
        "filters": data.get("filters"),
        "template": data.get("template"),
        "sql": truncate_sql(data.get("sql")),
        "row_count": data.get("row_count"),
        "latency_ms": data.get("latency_ms"),
        "error": data.get("error"),
    }


def parse_args() -> dict:
    p = argparse.ArgumentParser(description="medcare-data-qa audit logger")
    p.add_argument("--user-id")
    p.add_argument("--chat-id")
    p.add_argument("--question")
    p.add_argument("--metric")
    p.add_argument("--filters", help="JSON-encoded filter dict")
    p.add_argument("--template")
    p.add_argument("--sql")
    p.add_argument("--sql-stdin", action="store_true",
                   help="Read SQL from stdin instead of --sql")
    p.add_argument("--row-count", type=int)
    p.add_argument("--latency-ms", type=int)
    p.add_argument("--error", default=None)
    p.add_argument("--json-stdin", action="store_true",
                   help="Read full JSON record from stdin; ignore all flags")
    args = p.parse_args()

    if args.json_stdin:
        return json.load(sys.stdin)

    sql = args.sql
    if args.sql_stdin:
        sql = sys.stdin.read()

    filters = None
    if args.filters:
        try:
            filters = json.loads(args.filters)
        except json.JSONDecodeError:
            filters = args.filters

    return {
        "user_id": args.user_id,
        "chat_id": args.chat_id,
        "question": args.question,
        "metric": args.metric,
        "filters": filters,
        "template": args.template,
        "sql": sql,
        "row_count": args.row_count,
        "latency_ms": args.latency_ms,
        "error": args.error,
    }


def main() -> int:
    if not sys.stdin.isatty() and len(sys.argv) == 1:
        try:
            data = json.load(sys.stdin)
        except json.JSONDecodeError as exc:
            print(f"log_query: invalid JSON on stdin: {exc}", file=sys.stderr)
            return 2
    else:
        data = parse_args()

    record = build_record(data)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
