#!/usr/bin/env python3
"""Export every catalog identity and useful beverage context for alcohol review."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def export_manifest(database_path: Path, output_path: Path) -> int:
    connection = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    records = []
    rows = connection.execute(
        "SELECT source_id, source, name, brand, search_text FROM foods ORDER BY source, source_id"
    )
    for row in rows:
        record = {
            "source": row["source"],
            "source_id": row["source_id"],
            "name": row["name"],
            "brand": row["brand"],
            "source_category": None,
            "source_context": row["search_text"] or None,
            "default_components": [],
        }
        if row["source"] == "chaseFood":
            metadata = connection.execute(
                "SELECT category, food_kind FROM chase_food_metadata WHERE food_id = ?",
                (row["source_id"],),
            ).fetchone()
            if metadata:
                record["source_category"] = metadata["category"]
                record["food_kind"] = metadata["food_kind"]
            record["default_components"] = [
                {"source_id": component[0], "name": component[1], "grams": component[2]}
                for component in connection.execute(
                    """SELECT o.component_food_id, o.component_name, o.amount_grams
                       FROM chase_food_options o
                       WHERE o.parent_food_id = ? AND o.included_by_default = 1
                       ORDER BY o.display_order, o.component_food_id""",
                    (row["source_id"],),
                )
            ]
        records.append(record)
    connection.close()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as output:
        for record in records:
            output.write(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
    return len(records)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "CalorieTracker/Resources/FoodCatalog.sqlite3")
    parser.add_argument("--output", type=Path, default=ROOT / "data/food-catalog/alcohol-review-manifest.jsonl")
    args = parser.parse_args()
    count = export_manifest(args.input, args.output)
    print(f"Wrote {count:,} identities to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
