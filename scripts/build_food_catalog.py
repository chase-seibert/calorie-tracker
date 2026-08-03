#!/usr/bin/env python3
"""Build the compact on-device SQLite food catalog.

Uses only the Python standard library. Cached upstream inputs live under
data/downloads and are intentionally not committed; the derived SQLite catalog
is the app asset.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator


ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = ROOT / "data" / "downloads"

USDA_DOWNLOADS = {
    "foundation": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-04-30.zip",
    "sr_legacy": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip",
    "survey": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip",
}

OFF_SEARCH_URL = "https://world.openfoodfacts.org/api/v2/search"
OFF_FIELDS = ",".join(
    [
        "code",
        "product_name",
        "brands",
        "serving_size",
        "serving_quantity",
        "nutriments",
        "unique_scans_n",
    ]
)
USER_AGENT = "CalorieTracker/0.1 (personal local-first iOS app)"


@dataclass(frozen=True)
class CatalogFood:
    source_id: str
    source: str
    name: str
    brand: str | None
    barcode: str | None
    calories: float
    carbs: float
    fat: float
    protein: float
    base_grams: float = 100.0
    serving_grams: float | None = None
    serving_description: str | None = None
    portions: tuple[dict[str, object], ...] = ()
    rank: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download", action="store_true")
    parser.add_argument(
        "--off-pages",
        type=int,
        default=10,
        help="100 Open Food Facts products per page (default: 1,000 products)",
    )
    return parser.parse_args()


def download_file(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size > 0:
        print(f"Using cached {destination.name}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".partial")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    print(f"Downloading {url}")
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
    temporary.replace(destination)


def download_usda() -> None:
    for name, url in USDA_DOWNLOADS.items():
        download_file(url, DOWNLOADS / f"usda-{name}.zip")


def download_off(pages: int) -> None:
    destination = DOWNLOADS / f"open-food-facts-us-top-{pages * 100}.jsonl"
    if destination.exists() and destination.stat().st_size > 0:
        print(f"Using cached {destination.name}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".jsonl.partial")
    with temporary.open("w", encoding="utf-8") as output:
        for page in range(1, pages + 1):
            parameters = urllib.parse.urlencode(
                {
                    "countries_tags_en": "united-states",
                    "fields": OFF_FIELDS,
                    "page": page,
                    "page_size": 100,
                    "sort_by": "unique_scans_n",
                }
            )
            print(f"Downloading Open Food Facts page {page}/{pages}")
            payload = fetch_json_with_backoff(f"{OFF_SEARCH_URL}?{parameters}")
            for product in payload.get("products", []):
                output.write(json.dumps(product, ensure_ascii=False, separators=(",", ":")) + "\n")
            if page != pages:
                time.sleep(6.1)  # Respect the documented 10 search requests/minute.
    temporary.replace(destination)


def fetch_json_with_backoff(url: str, attempts: int = 6) -> dict:
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == attempts:
                raise
            retry_after = error.headers.get("Retry-After")
            delay = float(retry_after) if retry_after and retry_after.isdigit() else min(12 * attempt, 60)
            print(f"Open Food Facts returned HTTP {error.code}; retrying in {delay:g}s")
            time.sleep(delay)
        except urllib.error.URLError:
            if attempt == attempts:
                raise
            delay = min(8 * attempt, 40)
            print(f"Open Food Facts connection failed; retrying in {delay:g}s")
            time.sleep(delay)
    raise RuntimeError("Open Food Facts request exhausted retries")


def finite_number(value: object, default: float = 0.0) -> float:
    try:
        number = float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


def clean_text(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = " ".join(value.split()).strip()
    return normalized or None


def usda_foods() -> Iterator[CatalogFood]:
    for kind in USDA_DOWNLOADS:
        archive_path = DOWNLOADS / f"usda-{kind}.zip"
        if not archive_path.exists():
            continue
        print(f"Importing {archive_path.name}")
        with zipfile.ZipFile(archive_path) as archive:
            json_names = [name for name in archive.namelist() if name.lower().endswith(".json")]
            if not json_names:
                continue
            with archive.open(json_names[0]) as source:
                payload = json.load(source)
        collections = [value for value in payload.values() if isinstance(value, list)]
        if not collections:
            continue
        for raw in collections[0]:
            if not isinstance(raw, dict):
                continue
            parsed = parse_usda_food(raw, kind)
            if parsed:
                yield parsed


def parse_usda_food(raw: dict, kind: str) -> CatalogFood | None:
    name = clean_text(raw.get("description"))
    source_id = str(raw.get("fdcId") or "")
    if not name or not source_id:
        return None

    nutrient_values: dict[int, tuple[float, str]] = {}
    for entry in raw.get("foodNutrients") or []:
        nutrient = entry.get("nutrient") or {}
        nutrient_id = nutrient.get("id") or entry.get("nutrientId") or entry.get("nutrient_id")
        try:
            nutrient_id = int(nutrient_id)
        except (TypeError, ValueError):
            continue
        amount = finite_number(entry.get("amount"), float("nan"))
        if not math.isfinite(amount):
            continue
        unit = str(nutrient.get("unitName") or entry.get("unitName") or "")
        nutrient_values[nutrient_id] = (amount, unit)

    calories = first_nutrient(nutrient_values, [1008, 2047, 2048])
    if calories is None:
        return None
    calories_value, calories_unit = calories
    if calories_unit.lower() == "kj":
        calories_value /= 4.184

    portions: list[dict[str, object]] = []
    seen_portions: set[tuple[str, float]] = set()
    raw_portions = sorted(
        raw.get("foodPortions") or [],
        key=lambda portion: finite_number(portion.get("sequenceNumber"), 10_000),
    )
    for portion in raw_portions:
        grams = finite_number(portion.get("gramWeight"))
        if grams <= 0:
            continue
        amount = finite_number(portion.get("amount"), 1.0)
        measure = portion.get("measureUnit") or {}
        description = (
            clean_text(portion.get("portionDescription"))
            or clean_text(portion.get("modifier"))
            or clean_text(measure.get("name"))
        )
        if not description or description.lower() in {"quantity not specified", "undetermined"}:
            description = "serving"
        description = re.sub(r"^1\s+", "", description, flags=re.IGNORECASE)
        label = description
        if amount != 1:
            label = f"{amount:g} {label}"
        if "egg" in name.lower() and label.lower() in {
            "small", "medium", "large", "extra large", "jumbo"
        }:
            label += " egg"
        key = (label.lower(), round(grams, 4))
        if key in seen_portions:
            continue
        seen_portions.add(key)
        portion_id = str(portion.get("id") or f"{label}-{grams:g}")
        portions.append({"id": portion_id, "label": label, "grams": grams})

    serving_grams = finite_number(portions[0]["grams"]) if portions else None
    serving_description = f"1 {portions[0]['label']}" if portions else None
    data_type_rank = {"foundation": 300, "survey": 200, "sr_legacy": 100}.get(kind, 0)
    return CatalogFood(
        source_id=source_id,
        source="usda",
        name=name,
        brand=None,
        barcode=None,
        calories=max(calories_value, 0),
        carbs=max(first_amount(nutrient_values, 1005), 0),
        fat=max(first_amount(nutrient_values, 1004), 0),
        protein=max(first_amount(nutrient_values, 1003), 0),
        serving_grams=serving_grams,
        serving_description=serving_description,
        portions=tuple(portions),
        rank=data_type_rank,
    )


def first_nutrient(values: dict[int, tuple[float, str]], identifiers: list[int]) -> tuple[float, str] | None:
    for identifier in identifiers:
        if identifier in values:
            return values[identifier]
    return None


def first_amount(values: dict[int, tuple[float, str]], identifier: int) -> float:
    return values.get(identifier, (0.0, ""))[0]


def off_foods() -> Iterator[CatalogFood]:
    candidates = sorted(
        DOWNLOADS.glob("open-food-facts-us-top-*.jsonl"),
        key=lambda path: int(re.search(r"top-(\d+)", path.name).group(1)),  # type: ignore[union-attr]
    )
    if not candidates:
        return
    path = candidates[-1]
    print(f"Importing {path.name}")
    with path.open(encoding="utf-8") as source:
        for line in source:
            try:
                raw = json.loads(line)
            except json.JSONDecodeError:
                continue
            name = clean_text(raw.get("product_name"))
            barcode = re.sub(r"\D", "", str(raw.get("code") or ""))
            nutriments = raw.get("nutriments") or {}
            calories = finite_number(nutriments.get("energy-kcal_100g"), float("nan"))
            if not name or not barcode or not math.isfinite(calories) or calories < 0:
                continue
            serving_grams = finite_number(raw.get("serving_quantity"), 0)
            if serving_grams <= 0:
                serving_grams = parse_grams(clean_text(raw.get("serving_size"))) or 0
            serving_description = clean_text(raw.get("serving_size"))
            portion_label = re.sub(r"^1\s+", "", serving_description, flags=re.IGNORECASE) if serving_description else "serving"
            portions = (
                ({"id": "off-serving", "label": portion_label, "grams": serving_grams},)
                if serving_grams > 0
                else ()
            )
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
                serving_grams=serving_grams or None,
                serving_description=serving_description,
                portions=portions,
                rank=int(finite_number(raw.get("unique_scans_n"))),
            )


def parse_grams(text: str | None) -> float | None:
    if not text:
        return None
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*g\b", text, re.IGNORECASE)
    return float(match.group(1)) if match else None


def seed_foods() -> Iterable[CatalogFood]:
    # Small fallback used only when building without cached upstream data.
    return [
        CatalogFood("seed-banana", "usda", "Banana, raw", None, None, 89, 22.84, 0.33, 1.09, serving_grams=118, serving_description="1 medium"),
        CatalogFood("seed-egg", "usda", "Egg, whole, cooked, hard-boiled", None, None, 155, 1.12, 10.61, 12.58, serving_grams=50, serving_description="1 large"),
        CatalogFood("seed-chicken", "usda", "Chicken breast, roasted", None, None, 165, 0, 3.57, 31.02, serving_grams=85, serving_description="3 oz"),
        CatalogFood("737628064502", "off", "Greek Yogurt, Plain", "Fage", "737628064502", 97, 3, 5, 9, serving_grams=170, serving_description="170 g", rank=100),
        CatalogFood("049000028904", "off", "Sparkling Water", "Topo Chico", "049000028904", 0, 0, 0, 0, serving_grams=355, serving_description="355 ml", rank=80),
    ]


def create_database(output: Path, foods: Iterable[CatalogFood]) -> tuple[int, dict[str, int]]:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    database = sqlite3.connect(output)
    database.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA temp_store=MEMORY;
        CREATE TABLE foods (
            source_id TEXT NOT NULL,
            source TEXT NOT NULL,
            name TEXT NOT NULL,
            brand TEXT,
            barcode TEXT,
            calories REAL NOT NULL,
            carbs REAL NOT NULL,
            fat REAL NOT NULL,
            protein REAL NOT NULL,
            base_grams REAL NOT NULL,
            serving_grams REAL,
            serving_description TEXT,
            portions_json TEXT,
            rank INTEGER NOT NULL DEFAULT 0,
            UNIQUE(source, source_id)
        );
        CREATE INDEX foods_source_rank ON foods(source, rank DESC);
        CREATE INDEX foods_barcode ON foods(barcode) WHERE barcode IS NOT NULL;
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
    insert = """
        INSERT OR REPLACE INTO foods (
            source_id, source, name, brand, barcode, calories, carbs, fat,
            protein, base_grams, serving_grams, serving_description, portions_json,
            rank
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    count = 0
    counts: dict[str, int] = {}
    batch = []
    for food in foods:
        batch.append(
            (
                food.source_id,
                food.source,
                food.name,
                food.brand,
                food.barcode,
                food.calories,
                food.carbs,
                food.fat,
                food.protein,
                food.base_grams,
                food.serving_grams,
                food.serving_description,
                json.dumps(food.portions, separators=(",", ":")) if food.portions else None,
                food.rank,
            )
        )
        if len(batch) >= 2_000:
            database.executemany(insert, batch)
            count += len(batch)
            batch.clear()
    if batch:
        database.executemany(insert, batch)
        count += len(batch)
    for source, source_count in database.execute("SELECT source, count(*) FROM foods GROUP BY source"):
        counts[source] = source_count
    database.executescript(
        """
        CREATE VIRTUAL TABLE foods_fts USING fts5(
            name,
            brand,
            content='foods',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );
        INSERT INTO foods_fts(rowid, name, brand)
            SELECT rowid, name, coalesce(brand, '') FROM foods;
        INSERT INTO metadata VALUES ('schema_version', '2');
        INSERT INTO metadata VALUES ('usda_release', '2026-04-30 foundation; 2018-04 SR Legacy; 2024-10-31 FNDDS');
        INSERT INTO metadata VALUES ('off_scope', 'popular products tagged United States with calorie data');
        ANALYZE;
        VACUUM;
        """
    )
    database.close()
    return count, counts


def main() -> int:
    arguments = parse_args()
    if arguments.download:
        download_usda()
        download_off(arguments.off_pages)

    upstream = list(usda_foods()) + list(off_foods())
    foods: Iterable[CatalogFood]
    if upstream:
        foods = upstream
    else:
        print("No cached upstream files found; creating the fallback seed catalog.")
        foods = seed_foods()
    count, counts = create_database(arguments.output.resolve(), foods)
    print(f"Wrote {count:,} input records to {arguments.output.resolve()}")
    print("Final source counts: " + ", ".join(f"{key}={value:,}" for key, value in sorted(counts.items())))
    print(f"Database size: {arguments.output.stat().st_size / 1024 / 1024:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
