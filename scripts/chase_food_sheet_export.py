#!/usr/bin/env python3
"""Emit reproducible row data for syncing the Chase Food review spreadsheet."""

from __future__ import annotations
import json
import sys
from pathlib import Path


CATALOG = Path(__file__).resolve().parents[1] / "data/chase-food/catalog.json"


def number(value: object) -> float | None:
    try:
        parsed = float(value)
        return parsed if parsed else None
    except (TypeError, ValueError):
        return None


def load_rows(kind: str) -> list[list[object]]:
    source = json.loads(CATALOG.read_text())
    foods = source["foods"]
    counts = {level: sum(food["confidence"] == level for food in foods)
              for level in ("High", "Medium", "Low", "Unavailable")}
    if kind == "summary":
        review_count = sum(food["reviewRequired"] for food in foods)
        return [
            ["Chase Food · Nutrition Review", "2026-10-13"],
            [],
            ["Catalog identities", len(foods)],
            ["High confidence exact-name matches", counts["High"]],
            ["Medium confidence close matches", counts["Medium"]],
            ["Low confidence approximate matches", counts["Low"]],
            ["Unavailable profiles", counts["Unavailable"]],
            ["Needs refinement", review_count],
            ["Alias records", len(source["aliases"])],
            ["Configurable component options", len(source["suggestedAdditions"]) + len(source.get("baseCompositions", []))],
            ["Portion mappings", len(source["portions"])],
            ["Dataset revision", source["datasetVersion"]],
            ["Nutrition source", "Existing bundled catalog plus reviewed USDA FoodData Central enrichments where available"],
            ["Workbook source", source["workbookURL"]],
            [],
            ["Confidence method", "Direct authoritative source and portion match can be High; close but recipe-variable matches are Medium; approximate matches are Low."],
            ["Nutrition values", "Per-food evidence records document the source portion, per-100 g values, and scaling to the canonical default portion."],
            ["Limit", "Generic prepared-food records can differ from a user's recipe; unresolved composition and component amounts stay flagged for refinement."],
            ["Refinement rule", "Review every Low match, prepared dish, and record with missing fiber."],
            ["Synchronization", "This sheet is generated from data/chase-food/catalog.json, the manifest used by the app catalog builder."],
            ["Alias policy", "Brand and restaurant names point to generic canonical identities; no brand-specific nutrient claim."],
        ]
    if kind == "profiles":
        headers = ["Food ID", "Canonical food", "Category", "Food kind", "Default unit", "Default grams", "Calories / default", "Carbs g / default", "Fat g / default", "Protein g / default", "Fiber g / default", "Confidence", "Refinement needed", "Review reason", "Matched source", "Matched source ID", "Matched catalog name", "Match basis", "Similarity", "Available in search", "Evidence source URL", "Source serving", "Evidence reviewed", "Composition decision", "Baseline match", "Options (add-ons and variants)"]
        rows = []
        for food in foods:
            nutrients = food.get("nutrients") or {}
            match = food.get("nutritionSource") or {}
            evidence = food.get("nutritionEvidence") or {}
            source = evidence.get("source") or {}
            serving = source.get("serving") or {}
            rows.append([
                food["id"], food["name"], food["category"], food["foodKind"],
                food["defaultUnit"], food["defaultGrams"], nutrients.get("calories"),
                nutrients.get("carbs"), nutrients.get("fat"), nutrients.get("protein"),
                nutrients.get("fiber"), food["confidence"], "Yes" if food["reviewRequired"] else "No",
                "; ".join(food["reviewReasons"]), match.get("source", ""), match.get("sourceID", ""),
                match.get("name", ""), match.get("matchBasis", ""), match.get("similarity"),
                "No" if food.get("searchEnabled") is False else "Yes",
                "\n".join(dict.fromkeys(filter(None, [
                    source.get("url", ""),
                    *(component.get("url", "") for component in source.get("componentSources", [])),
                ]))),
                f"{serving['description']} ({serving['grams']} g)" if serving.get("description") and serving.get("grams") else "",
                source.get("reviewedDate", ""), (evidence.get("compositionEvidence") or {}).get("decision", ""),
                (
                    f"{food['baselineNutritionSource'].get('name', '')} "
                    f"({food['baselineNutritionSource'].get('source', '')}:"
                    f"{food['baselineNutritionSource'].get('sourceID', '')}; "
                    f"{food['baselineNutritionSource'].get('matchBasis', '')}; "
                    f"{food['baselineNutritionSource'].get('similarity', '')})"
                    if food.get("baselineNutritionSource") else ""
                ), food.get("optionsSummary", "None"),
            ])
        return [headers, *rows]
    if kind == "aliases":
        names = {food["id"]: food["name"] for food in foods}
        return [["Canonical food ID", "Canonical food", "Search alias", "Alias kind"], *[
            [alias["foodID"], names.get(alias["foodID"], ""), alias["alias"], alias["kind"]]
            for alias in source["aliases"]
        ]]
    if kind == "options":
        names = {food["id"]: food["name"] for food in foods}
        additions = [
            [row[0], names.get(row[0], row[1]), row[2], names.get(row[2], row[3]), number(row[10]), row[5], row[6], row[8] or "", row[9] or "multiple", number(row[4])]
            for row in source["suggestedAdditions"]
        ]
        included = [
            [row[0], names.get(row[0], row[1]), row[2], names.get(row[2], row[3]), number(row[4]), "Included", "Yes", "", "multiple", number(row[5])]
            for row in source.get("baseCompositions", [])
        ]
        return [["Parent food ID", "Canonical food", "Component food ID", "Component", "Amount g", "Relationship", "Selected by default", "Option group", "Selection mode", "Display order"], *additions, *included]
    if kind == "portions":
        names = {food["id"]: food["name"] for food in foods}
        return [["Portion ID", "Food ID", "Canonical food", "Portion label", "Portion key", "Quantity", "Grams", "Confidence", "Notes"], *[
            [row[0], row[1], names.get(row[1], ""), row[3], row[4], number(row[5]), number(row[6]), row[7], row[8]]
            for row in source["portions"]
        ]]
    raise ValueError(f"Unknown sheet data kind: {kind}")


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: chase_food_sheet_export.py summary|profiles|aliases|options|portions OFFSET LIMIT")
    kind, offset, limit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    rows = load_rows(kind)
    print(json.dumps(rows[offset:offset + limit], ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
