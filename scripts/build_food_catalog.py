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

# The .net host is the current API host used in the official examples and is
# less likely to redirect or reject long-running paginated downloads.
OFF_SEARCH_URL = "https://world.openfoodfacts.net/api/v2/search"
OFF_FULL_TEXT_SEARCH_URL = "https://search.openfoodfacts.org/search"
OFF_FIELDS = ",".join(
    [
        "code",
        "product_name",
        "brands",
        "serving_size",
        "serving_quantity",
        "nutriments",
        "categories_tags",
        "ingredients_tags",
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
    contains_processed_meat: bool = False
    contains_red_meat: bool = False
    rank: int = 0


PROCESSED_MEAT_PATTERN = re.compile(
    r"\b(?:bacon|ham|hot[ -]?dogs?|frankfurters?|wieners?|luncheon meat|cold cuts?|"
    r"deli meats?|sausages?|pepperoni|salami|prosciutto|pastrami|pancetta|mortadella|"
    r"capicola|coppa|soppressata|chorizo|kielbasa|bratwurst|andouille|liverwurst|"
    r"braunschweiger|corned beef|jerky|biltong|canned meat|spam)\b",
    re.IGNORECASE,
)
PROCESS_METHOD_PATTERN = re.compile(
    r"\b(?:cured|salted|smoked|fermented|dried|preserved)\b",
    re.IGNORECASE,
)
RED_MEAT_PATTERN = re.compile(
    r"\b(?:beef|veal|pork|lamb|mutton|goat|venison|deer|elk|moose|bison|buffalo|"
    r"rabbit|hare|horse|boar)\b",
    re.IGNORECASE,
)
OTHER_MEAT_PATTERN = re.compile(
    r"\b(?:chicken|turkey|duck|goose|poultry|meat|offal)\b",
    re.IGNORECASE,
)
POULTRY_PATTERN = re.compile(r"\b(?:chicken|turkey|duck|goose|poultry)\b", re.IGNORECASE)
MEAT_ANALOG_PATTERN = re.compile(
    r"\b(?:meatless|vegetarian|vegan|plant[ -]based|soy)\b",
    re.IGNORECASE,
)
NON_MEAT_RED_PRODUCT_PATTERN = re.compile(
    r"\b(?:beef|pork|lamb)\s+(?:broth|stock|bouillon|flavou?r|extract|gelatin|"
    r"tallow|fat|suet)\b",
    re.IGNORECASE,
)
NON_MUSCLE_MEAT_PATTERN = re.compile(
    r"\b(?:variety meats?|by-products?|brain|heart|kidney|liver|lung|pancreas|"
    r"spleen|sweetbread|thymus|tongue|tripe|seam fat|fat only)\b",
    re.IGNORECASE,
)
NON_MEAT_NAME_PATTERN = re.compile(
    r"\b(?:bun|buns|roll|rolls|bread|cracker|crackers|seasoning|flavou?r)\b",
    re.IGNORECASE,
)


def classify_meat_text(text: str, category: str = "") -> tuple[bool, bool]:
    """Return processed-meat and unprocessed-red-meat presence flags."""
    combined = f"{text} {category}".strip()
    processed_text = re.sub(r"\bleg\s*\(ham\)", "leg", combined, flags=re.IGNORECASE)
    processed_text = re.sub(r"\bham hocks?\b", "hock", processed_text, flags=re.IGNORECASE)
    processed_text = re.sub(
        r"\b(?:includes? )?cuts? to be cured\b",
        "cuts",
        processed_text,
        flags=re.IGNORECASE,
    )
    has_red_species = bool(RED_MEAT_PATTERN.search(combined))
    has_other_meat = bool(OTHER_MEAT_PATTERN.search(combined))
    has_poultry = bool(POULTRY_PATTERN.search(combined))
    is_analog = bool(MEAT_ANALOG_PATTERN.search(combined))
    if is_analog and not has_red_species and not has_poultry:
        return False, False

    category_lower = category.lower()
    processed_category = any(
        value in category_lower
        for value in (
            "sausages and luncheon meats",
            "cold cuts and cured meats",
            "deli and cured meat sandwiches",
            "bacon",
            "frankfurters",
            "sausages",
        )
    )
    explicit_processed = bool(PROCESSED_MEAT_PATTERN.search(processed_text))
    if explicit_processed and NON_MEAT_NAME_PATTERN.search(text) and not has_red_species and not has_poultry:
        explicit_processed = False
    method_processed = bool(PROCESS_METHOD_PATTERN.search(processed_text)) and (
        has_red_species or has_other_meat
    )
    contains_processed = processed_category or explicit_processed or method_processed

    red_category = any(
        value in category_lower
        for value in (
            "beef products",
            "pork products",
            "lamb, veal, and game products",
            "beef, excludes ground",
            "ground beef",
            "lamb, goat, game",
        )
    ) or category_lower == "pork"
    non_meat_product = bool(NON_MEAT_RED_PRODUCT_PATTERN.search(text))
    non_muscle_meat = bool(NON_MUSCLE_MEAT_PATTERN.search(text))
    contains_red = (
        (has_red_species or red_category)
        and not contains_processed
        and not non_meat_product
        and not non_muscle_meat
    )
    return contains_processed, contains_red


def classify_usda_meat(raw: dict) -> tuple[bool, bool]:
    category = clean_text((raw.get("foodCategory") or {}).get("description")) or clean_text(
        (raw.get("wweiaFoodCategory") or {}).get("wweiaFoodCategoryDescription")
    ) or ""
    direct = classify_meat_text(clean_text(raw.get("description")) or "", category)
    classifications = [direct]
    for ingredient in raw.get("inputFoods") or []:
        description = (
            clean_text(ingredient.get("ingredientDescription"))
            or clean_text(ingredient.get("foodDescription"))
            or ""
        )
        classifications.append(classify_meat_text(description))
    contains_processed = any(processed for processed, _ in classifications)
    contains_red = any(red for _, red in classifications)
    direct_processed_categories = (
        "sausages and luncheon meats",
        "cold cuts and cured meats",
        "bacon",
        "frankfurters",
        "sausages",
    )
    if direct[0] and any(value in category.lower() for value in direct_processed_categories):
        contains_red = False
    return contains_processed, contains_red


def classify_off_meat(raw: dict, name: str) -> tuple[bool, bool]:
    categories = " ".join(str(value) for value in raw.get("categories_tags") or [])
    ingredients = " ".join(str(value) for value in raw.get("ingredients_tags") or [])
    return classify_meat_text(f"{name} {ingredients}", categories)


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
    parser.add_argument(
        "--off-products",
        type=int,
        help="Select an exact cached Open Food Facts product set, such as 5,000 or 25,000",
    )
    parser.add_argument(
        "--off-search",
        action="store_true",
        help="Use the Search-a-licious U.S. popularity snapshot instead of the legacy API",
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


def download_off(pages: int, page_size: int = 100) -> None:
    destination = DOWNLOADS / f"open-food-facts-us-top-{pages * page_size}.jsonl"
    if destination.exists() and destination.stat().st_size > 0:
        print(f"Using cached {destination.name}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".jsonl.partial")
    progress = destination.with_suffix(".jsonl.progress")
    progress_is_compatible = False
    if progress.exists():
        progress_values = progress.read_text(encoding="utf-8").strip().split(",")
        if len(progress_values) == 2 and int(progress_values[1]) == page_size:
            start_page = int(progress_values[0]) + 1
            progress_is_compatible = True
        else:
            start_page = 1
    elif temporary.exists() and temporary.stat().st_size > 0:
        # A pre-progress partial from an earlier build contains complete pages:
        # each response is written atomically before the next request starts.
        line_count = sum(1 for _ in temporary.open(encoding="utf-8"))
        start_page = max(1, math.ceil(line_count / 100) + 1)
    else:
        start_page = 1
    mode = "a" if progress_is_compatible else "w"
    with temporary.open(mode, encoding="utf-8") as output:
        for page in range(start_page, pages + 1):
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
            output.flush()
            progress.write_text(f"{page},{page_size}", encoding="utf-8")
            if page != pages:
                time.sleep(6.1)  # Respect the documented 10 search requests/minute.
    temporary.replace(destination)
    progress.unlink(missing_ok=True)


def download_off_search(products: int) -> None:
    destination = DOWNLOADS / f"open-food-facts-search-us-filtered-top-{products}.jsonl"
    if destination.exists() and destination.stat().st_size > 0:
        print(f"Using cached {destination.name}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".jsonl.partial")
    page_size = min(products, 1_000)
    pages = math.ceil(products / page_size)
    progress = destination.with_suffix(".jsonl.progress")
    start_page = int(progress.read_text(encoding="utf-8")) + 1 if progress.exists() else 1
    mode = "a" if start_page > 1 else "w"
    with temporary.open(mode, encoding="utf-8") as output:
        for page in range(start_page, pages + 1):
            parameters = urllib.parse.urlencode(
                {
                    "q": 'countries_tags:"en:united-states"',
                    "sort_by": "unique_scans_n",
                    "page": page,
                    "page_size": page_size,
                }
            )
            print(f"Downloading Open Food Facts Search-a-licious page {page}/{pages}")
            payload = fetch_json_with_backoff(f"{OFF_FULL_TEXT_SEARCH_URL}?{parameters}")
            hits = payload.get("hits", [])
            for offset, product in enumerate(hits):
                if isinstance(product, dict):
                    product["_catalog_rank"] = products - ((page - 1) * page_size + offset)
                    output.write(json.dumps(product, ensure_ascii=False, separators=(",", ":")) + "\n")
            output.flush()
            progress.write_text(str(page), encoding="utf-8")
            if page != pages:
                time.sleep(6.1)
    temporary.replace(destination)
    progress.unlink(missing_ok=True)


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
    contains_processed_meat, contains_red_meat = classify_usda_meat(raw)
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
        contains_processed_meat=contains_processed_meat,
        contains_red_meat=contains_red_meat,
        rank=data_type_rank,
    )


def first_nutrient(values: dict[int, tuple[float, str]], identifiers: list[int]) -> tuple[float, str] | None:
    for identifier in identifiers:
        if identifier in values:
            return values[identifier]
    return None


def first_amount(values: dict[int, tuple[float, str]], identifier: int) -> float:
    return values.get(identifier, (0.0, ""))[0]


def off_foods(products: int | None = None, search: bool = False) -> Iterator[CatalogFood]:
    prefix = "open-food-facts-search-us-filtered-top-" if search else "open-food-facts-us-top-"
    candidates = {
        int(match.group(1)): path
        for path in DOWNLOADS.glob(f"{prefix}*.jsonl")
        if (match := re.search(r"top-(\d+)", path.name))
    }
    if not candidates:
        return
    if products is None:
        products = max(candidates)
    path = candidates.get(products)
    if path is None:
        available = ", ".join(f"{value:,}" for value in sorted(candidates))
        raise FileNotFoundError(
            f"No cached Open Food Facts set for {products:,} products; available: {available}"
        )
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
            contains_processed_meat, contains_red_meat = classify_off_meat(raw, name)
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
                contains_processed_meat=contains_processed_meat,
                contains_red_meat=contains_red_meat,
                rank=int(finite_number(raw.get("_catalog_rank", raw.get("unique_scans_n")))),
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
            contains_processed_meat INTEGER NOT NULL DEFAULT 0,
            contains_red_meat INTEGER NOT NULL DEFAULT 0,
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
            contains_processed_meat, contains_red_meat, rank
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                int(food.contains_processed_meat),
                int(food.contains_red_meat),
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
        INSERT INTO metadata VALUES ('schema_version', '3');
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
        if arguments.off_search:
            download_off_search(arguments.off_products or 10_000)
        elif arguments.off_products:
            download_off(1, page_size=arguments.off_products)
        else:
            download_off(arguments.off_pages)

    upstream = list(usda_foods()) + list(off_foods(arguments.off_products, search=arguments.off_search))
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
