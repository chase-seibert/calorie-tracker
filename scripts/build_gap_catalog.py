#!/usr/bin/env python3
"""Build an offline catalog containing generic USDA foods and targeted OFF gaps."""

from __future__ import annotations

import argparse
import urllib.parse
from pathlib import Path

from build_food_catalog import (
    OFF_FULL_TEXT_SEARCH_URL,
    CatalogFood,
    clean_text,
    create_database,
    fetch_json_with_backoff,
    finite_number,
    parse_grams,
    usda_foods,
)


QUERIES = ("psyllium", "americano", "buttermilk bread", "oroweat", "mint tea")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--per-query", type=int, default=100)
    return parser.parse_args()


def gap_foods(per_query: int):
    for query in QUERIES:
        parameters = urllib.parse.urlencode(
            {
                "q": query,
                "sort_by": "unique_scans_n",
                "page": 1,
                "page_size": per_query,
            }
        )
        print(f"Downloading Open Food Facts gap query: {query}")
        payload = fetch_json_with_backoff(f"{OFF_FULL_TEXT_SEARCH_URL}?{parameters}")
        for offset, raw in enumerate(payload.get("hits", [])):
            if not isinstance(raw, dict):
                continue
            name = clean_text(raw.get("product_name"))
            barcode = "".join(character for character in str(raw.get("code") or "") if character.isdigit())
            nutriments = raw.get("nutriments") or {}
            calories = finite_number(nutriments.get("energy-kcal_100g"), float("nan"))
            if not name or not barcode or calories != calories or calories < 0:
                continue
            serving_description = clean_text(raw.get("serving_size"))
            serving_grams = finite_number(raw.get("serving_quantity"), 0)
            if serving_grams <= 0:
                serving_grams = parse_grams(serving_description) or 0
            portions = (
                ({"id": "off-serving", "label": serving_description or "serving", "grams": serving_grams},)
                if serving_grams > 0
                else ()
            )
            fiber = finite_number(nutriments.get("fiber_100g"), float("nan"))
            yield CatalogFood(
                source_id=barcode,
                source="off",
                name=name,
                brand=clean_text(raw.get("brands")),
                barcode=barcode,
                calories=calories,
                carbs=max(finite_number(nutriments.get("carbohydrates_100g")), 0),
                fat=max(finite_number(nutriments.get("fat_100g")), 0),
                protein=max(finite_number(nutriments.get("proteins_100g")), 0),
                fiber=max(fiber, 0) if fiber == fiber else None,
                serving_grams=serving_grams or None,
                serving_description=serving_description,
                portions=portions,
                rank=per_query - offset,
            )


def main() -> int:
    arguments = parse_args()
    if arguments.per_query <= 0:
        raise ValueError("--per-query must be positive")
    foods = list(usda_foods()) + list(gap_foods(arguments.per_query))
    count, counts = create_database(arguments.output.resolve(), foods)
    print(f"Wrote {count:,} input records to {arguments.output.resolve()}")
    print("Final source counts: " + ", ".join(f"{key}={value:,}" for key, value in sorted(counts.items())))
    print(f"Database size: {arguments.output.stat().st_size / 1024 / 1024:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
