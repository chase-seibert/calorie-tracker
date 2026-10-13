#!/usr/bin/env python3
"""Match workbook identities to the bundled nutrition catalog and emit review data.

The generated catalog projection is also the source for the nutrition review
spreadsheet. Existing catalog nutrients are estimates when the identity is not
an exact food-name match; provenance and confidence travel with every row.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORKBOOK = ROOT / "data/chase-food/workbook.json"
DEFAULT_CATALOG = ROOT / "CalorieTracker/Resources/FoodCatalog.sqlite3"
DEFAULT_OUTPUT = ROOT / "data/chase-food/catalog.json"

RESTAURANT_ALIASES = {
    "food_burger": ["Five Guys", "McDonald's burger", "McDonalds burger", "Burger King burger", "Wendy's burger", "In-N-Out burger"],
    "food_pizza_slice": ["Domino's pizza", "Pizza Hut pizza", "Papa John's pizza", "Little Caesars pizza"],
    "food_tortilla_chips": ["Doritos", "Lay's chips", "Lays chips", "Ruffles"],
    "food_black_coffee": ["Starbucks coffee", "Dunkin coffee"],
}

# Basic deli sandwich searches now resolve to the configurable Sandwich record.
# Keep the former records in the catalog so existing diary history still resolves.
HISTORY_ONLY_FOODS = {
    "food_turkey_sandwich",
    "food_ham_sandwich",
    "food_deli_sandwich",
    "food_tuna_salad_sandwich",
    "food_chicken_sandwich",
}

# These rows are UI-only choices (such as a preparation style) and carry no
# food identity into search or the diary's component list.
INTERNAL_OPTION_FOODS = {
    "food_burnt_cheesecake_style",
    "food_regular_cheesecake_style",
}


def clean(value: object) -> str:
    return str(value or "").strip()


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return " ".join(re.findall(r"[a-z0-9]+", value))


def similarity(left: str, right: str) -> float:
    a, b = normalize(left), normalize(right)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    at, bt = set(a.split()), set(b.split())
    token = len(at & bt) / max(len(at | bt), 1)
    return max(SequenceMatcher(None, a, b).ratio(), token)


def load_existing(path: Path) -> list[dict]:
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    rows = [dict(row) for row in db.execute(
        "SELECT source_id, source, name, calories, carbs, fat, protein, fiber, base_grams, serving_grams, serving_description FROM foods WHERE source IN ('usda', 'off')"
    )]
    db.close()
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workbook", type=Path, default=DEFAULT_WORKBOOK)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    workbook = json.loads(args.workbook.read_text())
    foods_rows = workbook["foods"]
    food_headers = foods_rows[0]
    food_index = {name: food_headers.index(name) for name in food_headers}
    alias_by_food: dict[str, list[str]] = {}
    nutrition_alias_by_food: dict[str, list[str]] = {}
    alias_records: list[dict] = []
    for row in workbook["aliases"][1:]:
        if len(row) < 5 or clean(row[1]) != "food":
            continue
        food_id, alias = clean(row[2]), clean(row[0])
        alias_kind = clean(row[3]).lower() or "synonym"
        if alias:
            alias_by_food.setdefault(food_id, []).append(alias)
            alias_records.append({"foodID": food_id, "alias": alias, "kind": alias_kind})
            if alias_kind not in {"brand", "restaurant", "product"}:
                nutrition_alias_by_food.setdefault(food_id, []).append(alias)
    for food_id, values in RESTAURANT_ALIASES.items():
        for alias in values:
            alias_by_food.setdefault(food_id, []).append(alias)
            alias_records.append({"foodID": food_id, "alias": alias, "kind": "brand"})

    existing = load_existing(args.catalog)
    by_name: dict[str, list[dict]] = {}
    by_token: dict[str, list[dict]] = {}
    for item in existing:
        normalized_name = normalize(item["name"])
        by_name.setdefault(normalized_name, []).append(item)
        for token in set(normalized_name.split()):
            by_token.setdefault(token, []).append(item)
    output_foods: list[dict] = []
    for row in foods_rows[1:]:
        if len(row) <= food_index["Default grams (estimate)"]:
            continue
        food_id = clean(row[food_index["food_id"]])
        name = clean(row[food_index["Canonical food"]])
        if not food_id or not name:
            continue
        grams = float(clean(row[food_index["Default grams (estimate)"]]) or 100)
        aliases = list(dict.fromkeys(alias_by_food.get(food_id, [])))
        candidates: list[tuple[float, dict, str]] = [
            (1.0, record, "canonical") for record in by_name.get(normalize(name), [])
        ]
        candidate_records: dict[tuple[str, str], dict] = {}
        for token in set(normalize(name).split()):
            for record in by_token.get(token, []):
                candidate_records[(record["source"], record["source_id"])] = record
        for record in candidate_records.values():
            score = similarity(name, record["name"])
            if score >= .42:
                candidates.append((score, record, "canonical"))
        for alias in nutrition_alias_by_food.get(food_id, []):
            exact = by_name.get(normalize(alias), [])
            candidates.extend((.94, record, "alias") for record in exact)
        if not candidates:
            # Keep all workbook identities loggable, but make a weak fallback unmistakably low confidence.
            match = max(existing, key=lambda record: similarity(name, record["name"]))
            candidates.append((similarity(name, match["name"]), match, "fallback"))
        candidates.sort(key=lambda x: (-x[0], x[1]["source"] != "usda", x[1]["name"].lower()))
        score, match, match_basis = candidates[0] if candidates else (0.0, None, "none")
        confidence = "High" if match and score >= .999 else "Medium" if match and score >= .78 else "Low" if match else "Unavailable"
        review_reasons = []
        if not match:
            review_reasons.append("No reasonable match in existing catalog")
        elif confidence != "High":
            review_reasons.append("Approximate existing-catalog match; verify identity and preparation")
        if clean(row[food_index["Food kind"]]).lower().startswith(("recipe", "prepared")):
            review_reasons.append("Prepared dish; direct match may not represent recipe composition")
        if match and match["fiber"] is None:
            review_reasons.append("Fiber unavailable in matched record")
        nutrients = None
        if match:
            scale = grams / max(float(match["base_grams"] or 100), .01)
            nutrients = {key: round(float(match[key] or 0) * scale, 2) for key in ("calories", "carbs", "fat", "protein")}
            nutrients["fiber"] = round(float(match["fiber"]) * scale, 2) if match["fiber"] is not None else None
        if food_id in INTERNAL_OPTION_FOODS:
            nutrients = {"calories": 0, "carbs": 0, "fat": 0, "protein": 0, "fiber": 0}
        output_foods.append({
            "id": food_id, "name": name,
            "category": clean(row[food_index["Category"]]),
            "foodKind": clean(row[food_index["Food kind"]]),
            "defaultUnit": clean(row[food_index["Default human unit"]]),
            "defaultGrams": grams,
            "sizeAvailable": clean(row[food_index["S/M/L available?"]]).lower() == "yes",
            "aliases": aliases,
            "nutrients": nutrients,
            "nutritionPer100g": ({key: round(float(match[key] or 0), 4) for key in ("calories", "carbs", "fat", "protein")} | {"fiber": round(float(match["fiber"]), 4) if match["fiber"] is not None else None}) if match else None,
            "nutritionSource": {"source": match["source"], "sourceID": match["source_id"], "name": match["name"], "matchBasis": match_basis, "similarity": round(score, 4)} if match else None,
            "confidence": confidence,
            "reviewRequired": bool(review_reasons),
            "reviewReasons": review_reasons,
            "searchEnabled": food_id not in HISTORY_ONLY_FOODS | INTERNAL_OPTION_FOODS,
        })
    payload = {
        "schemaVersion": 1,
        "datasetVersion": "chase-food-2026-10-13-7",
        "workbookTitle": "Canonical U.S. Food Taxonomy — 514 Foods (Review Draft)",
        "workbookURL": "https://docs.google.com/spreadsheets/d/16Y1Uc0jldJ4tGO_vf5mgjT0n8pwJxO13W54zR5M_wWo/edit",
        "foods": output_foods,
        "aliases": alias_records,
        "portions": workbook["portions"][1:],
        "baseCompositions": workbook["baseCompositions"][1:],
        "suggestedAdditions": workbook["suggestedAdditions"][1:],
        "presets": workbook["presets"][1:],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    tally = {key: sum(food["confidence"] == key for food in output_foods) for key in ("High", "Medium", "Low", "Unavailable")}
    print(f"Prepared {len(output_foods)} foods; confidence: " + ", ".join(f"{k}={v}" for k, v in tally.items()))
    print(f"Review required: {sum(food['reviewRequired'] for food in output_foods)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
