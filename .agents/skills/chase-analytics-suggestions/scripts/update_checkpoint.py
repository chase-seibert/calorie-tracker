#!/usr/bin/env python3
"""Advance a private processed-through checkpoint after reviewing an analytics report."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import tempfile
import sys
from typing import Any


def parse_timestamp(value: Any, field: str) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise ValueError(f"Report is missing a valid {field} timestamp.")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"Report has an invalid {field} timestamp.") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"Report {field} timestamp must include a timezone.")
    return parsed.astimezone(dt.timezone.utc)


def timestamp_text(value: dt.datetime) -> str:
    return value.isoformat(timespec="microseconds").replace("+00:00", "Z")


def load_checkpoint(path: pathlib.Path) -> dict[str, Any]:
    if not path.exists():
        return {"schemaVersion": 1, "audiences": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schemaVersion") != 1 or not isinstance(data.get("audiences"), dict):
        raise ValueError("Checkpoint has an unsupported or malformed format.")
    return data


def write_atomic(path: pathlib.Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(data, indent=2, sort_keys=True) + "\n"
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(rendered)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def update(checkpoint_path: pathlib.Path, report_path: pathlib.Path, suggestions_reviewed: bool) -> None:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if not isinstance(report, dict) or report.get("namespace") != "calorie-tracker":
        raise ValueError("Report namespace must be calorie-tracker.")
    audience = report.get("audience")
    if audience not in {"production", "debug"}:
        raise ValueError("Report audience must be production or debug.")
    if suggestions_reviewed and audience != "debug":
        raise ValueError("Suggestions can only be marked reviewed for the Debug audience.")
    window_start = parse_timestamp(report.get("windowStart"), "windowStart")
    window_end = parse_timestamp(report.get("windowEnd"), "windowEnd")
    if window_start >= window_end:
        raise ValueError("Report windowStart must precede windowEnd.")
    if not isinstance(report.get("eventCounts"), dict):
        raise ValueError("Report is missing eventCounts.")

    checkpoint = load_checkpoint(checkpoint_path)
    entry = checkpoint["audiences"].setdefault(audience, {})
    previous_value = entry.get("processedThrough")
    if previous_value is not None and window_end < parse_timestamp(previous_value, "processedThrough"):
        raise ValueError("Refusing to move the processed-through timestamp backward.")

    now = timestamp_text(dt.datetime.now(dt.timezone.utc))
    entry.update({
        "processedThrough": timestamp_text(window_end),
        "windowStart": timestamp_text(window_start),
        "updatedAt": now,
        "eventCounts": report["eventCounts"],
    })
    if suggestions_reviewed:
        previous_suggestions = entry.get("suggestionsProcessedThrough")
        if previous_suggestions is not None and window_end < parse_timestamp(previous_suggestions, "suggestionsProcessedThrough"):
            raise ValueError("Refusing to move the suggestions timestamp backward.")
        entry["suggestionsProcessedThrough"] = timestamp_text(window_end)
    write_atomic(checkpoint_path, checkpoint)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", required=True, type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    parser.add_argument("--suggestions-reviewed", action="store_true")
    args = parser.parse_args()
    try:
        update(args.checkpoint, args.report, args.suggestions_reviewed)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"Analytics checkpoint: {exc}", file=sys.stderr)
        return 1
    print(f"Updated {args.checkpoint}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
