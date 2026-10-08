#!/usr/bin/env python3
"""Read Calorie Tracker search events from an Analytics Server SQLite export."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import pathlib
import sqlite3
import sys
from typing import Any


NAMESPACE = "calorie-tracker"
AUDIENCE = "production"
EVENT_TYPES = (
    "food_search.result_selected",
    "food_search.no_match",
    "food_search.nothing_selected",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=pathlib.Path, help="Analytics Server SQLite export")
    parser.add_argument("--days", type=int, default=90, help="Recent event window in days (default: 90)")
    parser.add_argument("--output", type=pathlib.Path, help="Optional local JSON output path")
    return parser.parse_args()


def parse_time(value: Any) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def read_only_connection(path: pathlib.Path) -> sqlite3.Connection:
    uri = path.resolve().as_uri() + "?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def validate_schema(connection: sqlite3.Connection) -> None:
    tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if "events" not in tables:
        raise ValueError("SQLite export has no events table.")
    columns = {row[1] for row in connection.execute("PRAGMA table_info(events)")}
    required = {"namespace", "event_type", "occurred_at", "app_version", "audience", "payload_json"}
    missing = sorted(required - columns)
    if missing:
        raise ValueError("SQLite events table is missing required columns: " + ", ".join(missing))


def safe_item_id(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    if value.startswith("food:usda:"):
        return value.removeprefix("food:")
    if value.startswith("food:off:"):
        return value.removeprefix("food:")
    if value.startswith("food:local:"):
        kind = "local-food"
    elif value.startswith("meal:local:"):
        kind = "local-meal"
    else:
        kind = "other"
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]
    return f"{kind}:{digest}"


def positive_int(value: Any) -> int | None:
    try:
        result = int(value)
    except (TypeError, ValueError):
        return None
    return result if result > 0 else None


def load_report(database: pathlib.Path, days: int) -> dict[str, Any]:
    if days <= 0:
        raise ValueError("--days must be positive.")
    if not database.is_file():
        raise ValueError(f"SQLite export does not exist: {database}")

    now = dt.datetime.now(dt.timezone.utc)
    start = now - dt.timedelta(days=days)
    connection = read_only_connection(database)
    try:
        validate_schema(connection)
        placeholders = ",".join("?" for _ in EVENT_TYPES)
        rows = connection.execute(
            f"""SELECT event_type, occurred_at, app_version, payload_json
                FROM events
                WHERE namespace = ? AND audience = ? AND event_type IN ({placeholders})
                ORDER BY occurred_at""",
            (NAMESPACE, AUDIENCE, *EVENT_TYPES),
        )
        counts: collections.Counter[str] = collections.Counter()
        by_query: dict[str, dict[str, Any]] = {}
        selection_events: list[dict[str, Any]] = []
        observed_times: list[dt.datetime] = []

        for row in rows:
            occurred = parse_time(row["occurred_at"])
            if occurred is None or occurred < start or occurred > now:
                continue
            event_type = row["event_type"]
            counts[event_type] += 1
            observed_times.append(occurred)
            try:
                payload = json.loads(row["payload_json"] or "{}")
            except (TypeError, ValueError):
                continue
            properties = payload.get("properties") if isinstance(payload, dict) else None
            if not isinstance(properties, dict):
                continue
            query = properties.get("query")
            if not isinstance(query, str) or not query.strip():
                continue
            query = query.strip()
            entry = by_query.setdefault(query, {
                "resultSelected": 0,
                "noMatch": 0,
                "nothingSelected": 0,
                "selectedItems": {},
            })

            if event_type == "food_search.no_match":
                entry["noMatch"] += 1
                continue
            if event_type == "food_search.nothing_selected":
                entry["nothingSelected"] += 1
                continue

            entry["resultSelected"] += 1
            item_id = safe_item_id(properties.get("selected_item_id"))
            rank = positive_int(properties.get("selected_rank"))
            if item_id is not None:
                item = entry["selectedItems"].setdefault(item_id, {"count": 0, "rankCounts": {}})
                item["count"] += 1
                if rank is not None:
                    rank_key = str(rank)
                    item["rankCounts"][rank_key] = item["rankCounts"].get(rank_key, 0) + 1
            above = properties.get("result_ids_above")
            above_ids = []
            if isinstance(above, str):
                above_ids = [safe_item_id(value) for value in above.split(",") if value]
                above_ids = [value for value in above_ids if value is not None]
            selection_events.append({
                "occurredAt": occurred.isoformat().replace("+00:00", "Z"),
                "appVersion": row["app_version"],
                "query": query,
                "selectedItemID": item_id,
                "selectedRank": rank,
                "resultIDsAbove": above_ids,
                "resultIDsAboveMayBeTruncated": isinstance(above, str) and len(above) >= 240,
            })

        query_rows = []
        for query, entry in sorted(by_query.items(), key=lambda item: (-sum(item[1][key] for key in ("resultSelected", "noMatch", "nothingSelected")), item[0].casefold())):
            selected_items = [
                {"itemID": item_id, **values}
                for item_id, values in sorted(entry["selectedItems"].items(), key=lambda item: (-item[1]["count"], item[0]))
            ]
            query_rows.append({"query": query, **{key: entry[key] for key in ("resultSelected", "noMatch", "nothingSelected")}, "selectedItems": selected_items})

        return {
            "schemaVersion": 1,
            "source": "Analytics Server SQLite export",
            "database": database.name,
            "namespace": NAMESPACE,
            "audience": AUDIENCE,
            "windowDays": days,
            "windowStart": start.isoformat().replace("+00:00", "Z"),
            "windowEnd": now.isoformat().replace("+00:00", "Z"),
            "observedStart": min(observed_times).isoformat().replace("+00:00", "Z") if observed_times else None,
            "observedEnd": max(observed_times).isoformat().replace("+00:00", "Z") if observed_times else None,
            "eventCounts": {event_type: counts[event_type] for event_type in EVENT_TYPES},
            "queries": query_rows,
            "selectionEvents": selection_events,
            "privacy": "No session IDs or names are emitted; local item IDs are replaced with stable short hashes.",
        }
    finally:
        connection.close()


def main() -> int:
    args = parse_args()
    try:
        report = load_report(args.db, args.days)
    except (OSError, sqlite3.Error, ValueError) as exc:
        print(f"Search analytics: {exc}", file=sys.stderr)
        return 1
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {args.output}")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
