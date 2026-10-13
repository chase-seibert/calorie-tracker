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
    fiber: float | None = None
    base_grams: float = 100.0
    serving_grams: float | None = None
    serving_description: str | None = None
    portions: tuple[dict[str, object], ...] = ()
    contains_processed_meat: bool = False
    contains_red_meat: bool = False
    rank: int = 0
    search_text: str = ""
    search_enabled: bool = True


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
    is_mixed_dish = bool(re.search(r"\b(?:sandwich|sub|salad|pizza|soup|burger)\b", text, re.IGNORECASE))
    if explicit_processed and NON_MEAT_NAME_PATTERN.search(text) and not has_red_species and not has_poultry and not is_mixed_dish:
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
        fiber=optional_amount(nutrient_values, 1079),
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


def optional_amount(values: dict[int, tuple[float, str]], identifier: int) -> float | None:
    value = values.get(identifier)
    return max(value[0], 0) if value is not None else None


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
                fiber=max(fiber, 0) if math.isfinite(fiber) else None,
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
        CatalogFood("seed-banana", "usda", "Banana, raw", None, None, 89, 22.84, 0.33, 1.09, fiber=2.6, serving_grams=118, serving_description="1 medium"),
        CatalogFood("seed-egg", "usda", "Egg, whole, cooked, hard-boiled", None, None, 155, 1.12, 10.61, 12.58, fiber=0, serving_grams=50, serving_description="1 large"),
        CatalogFood("seed-chicken", "usda", "Chicken breast, roasted", None, None, 165, 0, 3.57, 31.02, fiber=0, serving_grams=85, serving_description="3 oz"),
        CatalogFood("737628064502", "off", "Greek Yogurt, Plain", "Fage", "737628064502", 97, 3, 5, 9, fiber=0, serving_grams=170, serving_description="170 g", rank=100),
        CatalogFood("049000028904", "off", "Sparkling Water", "Topo Chico", "049000028904", 0, 0, 0, 0, fiber=0, serving_grams=355, serving_description="355 ml", rank=80),
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
            fiber REAL,
            base_grams REAL NOT NULL,
            serving_grams REAL,
            serving_description TEXT,
            portions_json TEXT,
            contains_processed_meat INTEGER NOT NULL DEFAULT 0,
            contains_red_meat INTEGER NOT NULL DEFAULT 0,
            search_text TEXT NOT NULL DEFAULT '',
            rank INTEGER NOT NULL DEFAULT 0,
            search_enabled INTEGER NOT NULL DEFAULT 1,
            UNIQUE(source, source_id)
        );
        CREATE INDEX foods_source_rank ON foods(source, rank DESC);
        CREATE INDEX foods_barcode ON foods(barcode) WHERE barcode IS NOT NULL;
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE chase_food_metadata (
            food_id TEXT PRIMARY KEY, category TEXT NOT NULL, food_kind TEXT NOT NULL,
            confidence TEXT NOT NULL, review_required INTEGER NOT NULL,
            match_source TEXT, match_source_id TEXT, match_name TEXT, match_basis TEXT,
            similarity REAL, review_reasons_json TEXT NOT NULL,
            nutrition_evidence_json TEXT, baseline_source_json TEXT
        );
        CREATE TABLE chase_food_aliases (
            food_id TEXT NOT NULL, alias TEXT NOT NULL, kind TEXT NOT NULL,
            PRIMARY KEY(food_id, alias)
        );
        CREATE INDEX chase_food_alias_lookup ON chase_food_aliases(alias COLLATE NOCASE);
        CREATE TABLE chase_food_options (
            parent_food_id TEXT NOT NULL, option_id TEXT NOT NULL, component_food_id TEXT NOT NULL,
            component_name TEXT NOT NULL, amount_grams REAL NOT NULL, relationship TEXT NOT NULL,
            included_by_default INTEGER NOT NULL, display_order INTEGER NOT NULL,
            option_group TEXT, selection_mode TEXT NOT NULL DEFAULT 'multiple',
            PRIMARY KEY(parent_food_id, option_id)
        );
        CREATE INDEX chase_food_options_parent ON chase_food_options(parent_food_id, included_by_default, display_order);
        """
    )
    insert = """
        INSERT OR REPLACE INTO foods (
            source_id, source, name, brand, barcode, calories, carbs, fat,
            protein, fiber, base_grams, serving_grams, serving_description, portions_json,
            contains_processed_meat, contains_red_meat, rank, search_text, search_enabled
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                food.fiber,
                food.base_grams,
                food.serving_grams,
                food.serving_description,
                json.dumps(food.portions, separators=(",", ":")) if food.portions else None,
                int(food.contains_processed_meat),
                int(food.contains_red_meat),
                food.rank,
                food.search_text,
                int(food.search_enabled),
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
            search_text,
            content='foods',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );
        INSERT INTO foods_fts(rowid, name, brand, search_text)
            SELECT rowid, name, coalesce(brand, ''), search_text FROM foods WHERE search_enabled = 1;
        INSERT INTO metadata VALUES ('schema_version', '5');
        INSERT INTO metadata VALUES ('usda_release', '2026-04-30 foundation; 2018-04 SR Legacy; 2024-10-31 FNDDS');
        INSERT INTO metadata VALUES ('off_scope', 'popular products tagged United States with calorie data');
        ANALYZE;
        VACUUM;
        """
    )
    database.close()
    return count, counts


def existing_catalog(path: Path) -> list[CatalogFood]:
    """Preserve the installed catalog when upstream downloads are absent."""
    if not path.exists():
        return []
    try:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        records = []
        for row in connection.execute("SELECT * FROM foods"):
            records.append(CatalogFood(
                source_id=row["source_id"], source=row["source"], name=row["name"],
                brand=row["brand"], barcode=row["barcode"], calories=row["calories"],
                carbs=row["carbs"], fat=row["fat"], protein=row["protein"], fiber=row["fiber"],
                base_grams=row["base_grams"], serving_grams=row["serving_grams"],
                serving_description=row["serving_description"],
                portions=tuple(json.loads(row["portions_json"] or "[]")),
                contains_processed_meat=bool(row["contains_processed_meat"]),
                contains_red_meat=bool(row["contains_red_meat"]), rank=row["rank"],
                search_text=row["search_text"] if "search_text" in row.keys() else "",
                search_enabled=bool(row["search_enabled"]) if "search_enabled" in row.keys() else True,
            ))
        connection.close()
        return records
    except (sqlite3.Error, KeyError, ValueError, TypeError):
        return []


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
        retained = existing_catalog(arguments.output.resolve())
        if retained:
            print(f"No cached upstream files found; retaining {len(retained):,} records from the existing catalog.")
            foods = retained
        else:
            print("No cached upstream files or existing catalog found; creating the fallback seed catalog.")
            foods = seed_foods()
    chase_path = ROOT / "data/chase-food/catalog.json"
    if chase_path.exists():
        chase = json.loads(chase_path.read_text(encoding="utf-8"))
        portions_by_food: dict[str, list[dict[str, object]]] = {}
        portion_rows = chase.get("portions", [])
        if portion_rows:
            for raw in portion_rows:
                if len(raw) < 7:
                    continue
                portion_id, food_id, _, display, size, quantity, grams = raw[:7]
                try:
                    amount_grams = float(grams)
                except (TypeError, ValueError):
                    continue
                # The workbook's display column is the user-facing portion
                # label. Size remains structured metadata for review and sort.
                label = str(display or "serving")
                portions_by_food.setdefault(str(food_id), []).append({"id": str(portion_id), "label": label, "grams": amount_grams})
        chase_foods = []
        database_metadata = []
        option_rows = []
        canonical_by_id = {item["id"]: item for item in chase.get("foods", [])}
        for index, row in enumerate(chase.get("suggestedAdditions", [])):
            if len(row) < 8:
                continue
            parent_id, _, component_id, component_name, display_order = row[:5]
            included = str(row[6]).strip().lower() == "yes"
            option_group = str(row[8]).strip() if len(row) > 8 and row[8] else None
            selection_mode = str(row[9]).strip().lower() if len(row) > 9 and row[9] else "multiple"
            component = canonical_by_id.get(component_id)
            default_amount = float(component.get("defaultGrams") or 30) if component else 30.0
            try:
                amount_value = row[10] if len(row) > 10 else None
                amount = float(amount_value) if amount_value else default_amount
            except (TypeError, ValueError):
                amount = default_amount
            option_rows.append((parent_id, f"addition:{component_id}", component_id, component_name, amount,
                                str(row[5] or "addition"), int(included), int(display_order or index),
                                option_group, selection_mode))
        for index, row in enumerate(chase.get("baseCompositions", [])):
            if len(row) < 6:
                continue
            parent_id, _, component_id, component_name, grams, display_order = row[:6]
            try:
                amount = float(grams)
            except (TypeError, ValueError):
                continue
            option_rows.append((parent_id, f"included:{component_id}", component_id, component_name, amount,
                                "included", 1, int(display_order or index), None, "multiple"))
        for item in chase.get("foods", []):
            nutrients = item.get("nutrients") or {"calories": 0, "carbs": 0, "fat": 0, "protein": 0, "fiber": None}
            serving_grams = float(item.get("defaultGrams") or 100)
            portions = portions_by_food.get(item["id"], [])
            if not portions:
                portions = [{"id": f"prt_{item['id']}_default", "label": str(item.get("defaultUnit") or "serving"), "grams": serving_grams}]
            aliases = [str(alias) for alias in item.get("aliases", [])]
            chase_foods.append(CatalogFood(
                source_id=item["id"], source="chaseFood", name=item["name"], brand=None, barcode=None,
                calories=float(nutrients.get("calories") or 0), carbs=float(nutrients.get("carbs") or 0),
                fat=float(nutrients.get("fat") or 0), protein=float(nutrients.get("protein") or 0),
                fiber=float(nutrients["fiber"]) if nutrients.get("fiber") is not None else None,
                base_grams=serving_grams, serving_grams=serving_grams,
                serving_description=str(item.get("defaultUnit") or "serving"), portions=tuple(portions),
                search_text=" ".join(aliases), rank=50,
                search_enabled=bool(item.get("searchEnabled", True)),
            ))
            provenance = item.get("nutritionSource") or {}
            database_metadata.append((
                item["id"], item.get("category", ""), item.get("foodKind", ""),
                item.get("confidence", "Unavailable"), int(bool(item.get("reviewRequired"))),
                provenance.get("source"), provenance.get("sourceID"), provenance.get("name"),
                provenance.get("matchBasis"), provenance.get("similarity"),
                json.dumps(item.get("reviewReasons", []), separators=(",", ":")),
                json.dumps(item.get("nutritionEvidence"), separators=(",", ":")) if item.get("nutritionEvidence") else None,
                json.dumps(item.get("baselineNutritionSource"), separators=(",", ":")) if item.get("baselineNutritionSource") else None,
            ))
        payload_aliases = [(a["foodID"], a["alias"], a.get("kind", "synonym")) for a in chase.get("aliases", [])]
        foods = list(foods) + chase_foods
    count, counts = create_database(arguments.output.resolve(), foods)
    if chase_path.exists():
        with sqlite3.connect(arguments.output.resolve()) as database:
            database.executemany("INSERT INTO chase_food_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", database_metadata)
            database.executemany("INSERT OR IGNORE INTO chase_food_aliases VALUES (?, ?, ?)", payload_aliases)
            database.executemany("INSERT OR REPLACE INTO chase_food_options VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", option_rows)
            database.executemany(
                "INSERT INTO metadata VALUES (?, ?)",
                [("chase_food_dataset_version", chase["datasetVersion"]),
                 ("chase_food_identity_count", str(len(database_metadata)))],
            )
    print(f"Wrote {count:,} input records to {arguments.output.resolve()}")
    print("Final source counts: " + ", ".join(f"{key}={value:,}" for key, value in sorted(counts.items())))
    print(f"Database size: {arguments.output.stat().st_size / 1024 / 1024:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
