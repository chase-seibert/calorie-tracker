#!/usr/bin/env python3
"""Build an experimental family/variant food identity catalog.

The production catalog is read-only input. The generated database preserves a
three-level model:

    canonical food family -> structured variants -> original source records

``foods`` and ``foods_fts`` expose one default variant per family so the file can
be exercised with the app's existing catalog search shape. ``variant_foods`` and
``variant_foods_fts`` provide the more detailed alternative for future searches
that contain preparation intent such as "raw" or "fried".

The implementation intentionally uses deterministic entity resolution rather
than opaque clustering: attributes are auditable, nutrition remains attached to
a variant, and ambiguous families are called out in the generated HTML report.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import re
import shutil
import sqlite3
import statistics
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

from build_grouped_food_catalog import (
    Food,
    catalog_search,
    file_size_mib,
    normalized_text,
    nutrition_distance,
    read_foods,
    representative_penalty,
)


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "CalorieTracker" / "Resources" / "FoodCatalog.sqlite3"
DEFAULT_OUTPUT = ROOT / "data" / "work" / "catalogs" / "food-family-catalog.sqlite3"
DEFAULT_REPORT = ROOT / "data" / "work" / "catalog-reports" / "food-family-catalog.html"
ALGORITHM_VERSION = "identity-1"

COOKING_METHODS = (
    "hard boiled",
    "pan browned",
    "oven roasted",
    "baked",
    "boiled",
    "braised",
    "broiled",
    "cooked",
    "fried",
    "grilled",
    "microwaved",
    "poached",
    "roasted",
    "sauteed",
    "scrambled",
    "simmered",
    "steamed",
    "stewed",
    "toasted",
)
PRESERVATION_METHODS = ("canned", "dried", "freeze dried", "frozen", "pickled", "smoked")
COATING_WORDS = {"batter", "breaded", "breading", "coated", "coating", "flour"}
SAUCE_WORDS = {"barbecue", "bbq", "glazed", "marinade", "marinated", "sauce"}
RESTAURANT_MARKERS = {
    "arbys",
    "burger king",
    "chick fil a",
    "dennys",
    "dominos",
    "fast foods",
    "kfc",
    "mcdonalds",
    "papa johns",
    "pizza hut",
    "popeyes",
    "subway",
    "taco bell",
    "wendys",
}
POULTRY_WORDS = {"chicken", "duck", "goose", "turkey"}
POULTRY_PARTS = {
    "back",
    "breast",
    "dark",
    "drumstick",
    "feet",
    "giblets",
    "gizzard",
    "heart",
    "leg",
    "light",
    "liver",
    "neck",
    "skin",
    "tail",
    "thigh",
    "wing",
}
PRODUCT_FORMS = {
    "benedict",
    "creamed",
    "deli",
    "deviled",
    "luncheon",
    "meatless",
    "nuggets",
    "omelet",
    "patty",
    "roll",
    "rolls",
    "salad",
    "sandwich",
    "tenders",
}
EGG_SPECIES = {"chicken", "duck", "goose", "quail", "turkey"}
EGG_FORMULATION_WORDS = {
    "added",
    "animal",
    "cooking",
    "drippings",
    "fat",
    "fresh",
    "glucose",
    "margarine",
    "no",
    "oil",
    "pasteurized",
    "reduced",
    "salted",
    "spray",
    "stabilized",
    "sugared",
}
REPORT_SEARCHES = (
    "chicken",
    "chicken breast",
    "egg",
    "egg whole",
    "salmon",
    "rice",
    "milk",
    "butter",
)


@dataclass(frozen=True)
class Identity:
    family_key: str
    family_title: str
    state: str
    preparation: str
    preservation: str
    skin: str
    coating: str
    sauce: str
    cooking_medium: str
    additions: str
    product_form: str
    context: str
    confidence: str
    review_reason: str

    @property
    def variant_key(self) -> str:
        values = (
            self.state,
            self.preparation,
            self.preservation,
            self.skin,
            self.coating,
            self.sauce,
            self.cooking_medium,
            self.additions,
            self.product_form,
            self.context,
        )
        return "|".join(value or "-" for value in values)


@dataclass(frozen=True)
class Variant:
    variant_id: str
    family_id: str
    title: str
    identity: Identity
    canonical: Food
    members: tuple[Food, ...]


@dataclass(frozen=True)
class Family:
    family_id: str
    family_key: str
    title: str
    default_variant: Variant
    variants: tuple[Variant, ...]
    members: tuple[Food, ...]
    confidence: str
    review_reason: str
    aliases: str

    @property
    def calorie_min(self) -> float:
        return min(food.calories for food in self.members)

    @property
    def calorie_max(self) -> float:
        return max(food.calories for food in self.members)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def has_phrase(name: str, phrase: str) -> bool:
    return re.search(rf"\b{re.escape(phrase)}\b", name) is not None


def matching_values(name: str, values: tuple[str, ...]) -> list[str]:
    return [value for value in values if has_phrase(name, value)]


def restaurant_name(name: str) -> bool:
    return any(marker in name for marker in RESTAURANT_MARKERS)


def human_title(tokens: list[str], fallback: str) -> str:
    if not tokens:
        return fallback
    if tokens[0] == "egg":
        named_form = next((token for token in tokens if token in sorted(PRODUCT_FORMS)), None)
        if named_form:
            qualifier = next((token for token in tokens if token in {"substitute", "white"}), None)
            return " ".join(part for part in ("Egg", qualifier, named_form) if part)
        if len(tokens) > 1 and tokens[1] in {"custard", "custards", "nog", "nogs"}:
            text = " ".join(tokens)
            return text[:1].upper() + text[1:]
        species = next((token for token in tokens if token in EGG_SPECIES), None)
        component = next((token for token in tokens if token in {"white", "whole", "yolk"}), None)
        prefix = f"{species.capitalize()} egg" if species and species != "chicken" else "Egg"
        if component:
            ignored = {"egg", component}
            if species:
                ignored.add(species)
            extras = [token for token in tokens if token not in ignored]
            if component == "whole" and prefix == "Egg" and not extras:
                return "Egg"
            base = f"{prefix}, {component}"
            return f"{base}, {' '.join(extras)}" if extras else base
        if len(tokens) > 1:
            text = " ".join(tokens)
            return text[:1].upper() + text[1:]
        return prefix
    text = " ".join(tokens)
    return text[:1].upper() + text[1:]


def source_product_identity(food: Food, name: str, context: str) -> Identity:
    brand = normalized_text(food.brand or "")
    key = f"product|{food.source}|{brand}|{name}"
    return Identity(
        family_key=key,
        family_title=food.name,
        state="",
        preparation="",
        preservation="",
        skin="",
        coating="",
        sauce="",
        cooking_medium="",
        additions="",
        product_form="product",
        context=context,
        confidence="high",
        review_reason="",
    )


def parse_identity(food: Food) -> Identity:
    name = normalized_text(food.name)
    tokens = name.split()
    token_set = set(tokens)
    named_context = "branded" if food.brand else "restaurant" if restaurant_name(name) else "generic"
    if food.source != "usda" or named_context != "generic":
        return source_product_identity(food, name, named_context)
    context = "restaurant preparation" if "fast food restaurant" in name or "from fast food" in name else "generic"

    raw = "raw" in token_set
    preparation_values = matching_values(name, COOKING_METHODS)
    preservation_values = matching_values(name, PRESERVATION_METHODS)
    preparation_values = [
        value for value in preparation_values
        if value != "cooked" or len(preparation_values) == 1
    ]
    preparation = ", ".join(
        value for value in preparation_values if not any(value in other and value != other for other in preparation_values)
    )
    preservation = ", ".join(preservation_values)
    state = "cooked" if preparation_values else "raw" if raw else ""

    if "skin only" in name:
        skin = "skin only"
    elif "skin not eaten" in name or "skinless" in token_set or "meat only" in name:
        skin = "skinless"
    elif "skin eaten" in name or "meat and skin" in name:
        skin = "skin on"
    else:
        skin = ""

    coating_values = sorted(token_set & COATING_WORDS)
    sauce_values = sorted(token_set & SAUCE_WORDS)
    coating = "breaded/coated" if coating_values else ""
    sauce = "sauced/marinated" if sauce_values else ""

    if "with cooking spray" in name:
        cooking_medium = "cooking spray"
    elif "with animal fat" in name or "meat drippings" in name:
        cooking_medium = "animal fat"
    elif "with margarine" in name:
        cooking_medium = "margarine"
    elif "with butter" in name:
        cooking_medium = "butter"
    elif "with oil" in name:
        cooking_medium = "oil"
    elif "fat added" in name:
        cooking_medium = "fat added"
    elif "no added fat" in name:
        cooking_medium = "no added fat"
    else:
        cooking_medium = ""

    if tokens and tokens[0] == "egg":
        product_form = next(
            (form for form in ("omelet", "sandwich", "salad", "rolls", "roll", "benedict", "deviled", "creamed") if form in token_set),
            "",
        )
    else:
        product_form = next((form for form in sorted(PRODUCT_FORMS) if form in token_set), "")
    if product_form == "rolls":
        product_form = "roll"
    additions = ""
    removable = {
        token
        for phrase in (*COOKING_METHODS, *PRESERVATION_METHODS)
        for token in phrase.split()
    }
    removable |= COATING_WORDS | {"raw", "reheated", "heated", "precooked"}

    if token_set & POULTRY_WORDS:
        removable |= {
            "added",
            "and",
            "as",
            "and",
            "bbq",
            "boneless",
            "broiler",
            "broilers",
            "eaten",
            "fast",
            "food",
            "from",
            "fryer",
            "fryers",
            "marinade",
            "marinated",
            "meat",
            "meatless",
            "not",
            "only",
            "or",
            "original",
            "restaurant",
            "rotisserie",
            "sauce",
            "seasoning",
            "skinless",
            "solution",
            "to",
            "with",
            "without",
        }
        if "meat" in token_set or any(part in token_set for part in POULTRY_PARTS - {"skin"}):
            removable.add("skin")

    if tokens and tokens[0] == "egg":
        removable |= EGG_FORMULATION_WORDS | {
            "as",
            "butter",
            "fast",
            "food",
            "from",
            "includes",
            "method",
            "made",
            "meat",
            "ns",
            "nfs",
            "on",
            "only",
            "or",
            "restaurant",
            "distribution",
            "foods",
            "for",
            "program",
            "s",
            "to",
            "type",
            "usda",
            "with",
        }
        # Named egg dishes remain distinct food families rather than variants.
        removable -= PRODUCT_FORMS

    core_tokens = [token for token in tokens if token not in removable]
    if tokens and tokens[0] == "egg" and product_form in {"omelet", "roll", "salad", "sandwich"}:
        component = next((token for token in tokens if token in {"substitute", "white"}), None)
        core_tokens = ["egg"] + ([component] if component else []) + [product_form]
        addition_values: list[str] = []
        for phrase in (
            "bacon",
            "biscuit",
            "cheese",
            "chicken",
            "english muffin",
            "ham",
            "meat",
            "meatless",
            "pancake",
            "pork",
            "sausage",
            "tomatoes",
            "dark green vegetables",
            "vegetables",
            "potatoes",
            "onions",
        ):
            if has_phrase(name, phrase):
                addition_values.append(phrase)
        additions = ", ".join(
            value for value in addition_values
            if value != "vegetables" or not any("vegetables" in other and other != value for other in addition_values)
        )
    if not core_tokens:
        core_tokens = tokens

    family_title = human_title(core_tokens, food.name)
    family_key = "generic|" + " ".join(core_tokens)
    reasons: list[str] = []
    if len(core_tokens) == 1 and core_tokens[0] in {"chicken", "egg", "fish", "turkey"}:
        reasons.append("broad one-token family")
    if "skin only" in name and "skin" not in core_tokens:
        reasons.append("skin-only record shares a broader family")
    confidence = "review" if reasons else "high"
    return Identity(
        family_key=family_key,
        family_title=family_title,
        state=state,
        preparation=preparation,
        preservation=preservation,
        skin=skin,
        coating=coating,
        sauce=sauce,
        cooking_medium=cooking_medium,
        additions=additions,
        product_form=product_form,
        context=context,
        confidence=confidence,
        review_reason="; ".join(reasons),
    )


def canonical_member(members: tuple[Food, ...]) -> Food:
    return min(
        members,
        key=lambda food: (
            round(nutrition_distance(food, members), 6),
            representative_penalty(food),
            -food.rank,
            0 if food.serving_grams else 1,
            len(food.name),
            food.source_id,
        ),
    )


def variant_title(family_title: str, identity: Identity) -> str:
    parts = [
        identity.state,
        identity.preparation,
        identity.preservation,
        identity.skin,
        identity.coating,
        identity.sauce,
        identity.cooking_medium,
        identity.additions,
    ]
    suffix = ", ".join(dict.fromkeys(part for part in parts if part))
    return f"{family_title} — {suffix}" if suffix else family_title


def default_variant_score(variant: Variant) -> tuple[object, ...]:
    identity = variant.identity
    family_tokens = set(normalized_text(identity.family_title).split())
    meat_or_staple = bool(family_tokens & (POULTRY_WORDS | {"beef", "egg", "pasta", "pork", "rice"}))
    penalty = 0
    penalty += 30 if identity.context != "generic" else 0
    penalty += 18 if identity.coating else 0
    penalty += 15 if identity.sauce else 0
    penalty += 10 if identity.cooking_medium not in {"", "no added fat"} else 0
    penalty += 6 if identity.additions else 0
    penalty += 10 if identity.skin in {"skin on", "skin only"} else 0
    penalty += 8 if "dried" in identity.preservation else 0
    penalty += 4 if identity.preservation in {"canned", "frozen", "pickled", "smoked"} else 0
    if meat_or_staple:
        penalty -= 6 if identity.state == "cooked" else 0
        penalty += 4 if identity.state == "raw" else 0
        penalty -= 3 if identity.preparation in {"baked", "broiled", "grilled", "roasted"} else 0
    else:
        penalty += 1 if identity.state == "cooked" else 0
    penalty -= 3 if identity.skin == "skinless" else 0
    if "egg" in family_tokens:
        penalty -= 6 if any(method in identity.preparation for method in {"boiled", "poached"}) else 0
        penalty += 4 if any(method in identity.preparation for method in {"baked", "fried"}) else 0
    penalty -= 2 if not any(
        (
            identity.state,
            identity.preparation,
            identity.preservation,
            identity.skin,
            identity.coating,
            identity.sauce,
            identity.cooking_medium,
            identity.additions,
        )
    ) else 0
    return (
        penalty,
        representative_penalty(variant.canonical),
        -variant.canonical.rank,
        len(variant.canonical.name),
        variant.variant_id,
    )


def build_families(foods: list[Food]) -> list[Family]:
    family_buckets: dict[str, list[tuple[Food, Identity]]] = defaultdict(list)
    for food in foods:
        identity = parse_identity(food)
        family_buckets[identity.family_key].append((food, identity))

    families: list[Family] = []
    for family_key, entries in family_buckets.items():
        family_digest = hashlib.sha1(family_key.encode(), usedforsecurity=False).hexdigest()[:16]
        family_id = f"fam-{family_digest}"
        variant_buckets: dict[str, list[tuple[Food, Identity]]] = defaultdict(list)
        for food, identity in entries:
            variant_buckets[identity.variant_key].append((food, identity))

        variants: list[Variant] = []
        for variant_key, variant_entries in variant_buckets.items():
            members = tuple(sorted((entry[0] for entry in variant_entries), key=lambda food: (food.source, food.source_id)))
            identity = variant_entries[0][1]
            representative = canonical_member(members)
            variant_digest = hashlib.sha1(
                f"{family_key}|{variant_key}".encode(), usedforsecurity=False
            ).hexdigest()[:16]
            variants.append(
                Variant(
                    variant_id=f"var-{variant_digest}",
                    family_id=family_id,
                    title=variant_title(identity.family_title, identity),
                    identity=identity,
                    canonical=representative,
                    members=members,
                )
            )
        variants.sort(key=lambda variant: (default_variant_score(variant), variant.title.casefold()))
        default_variant = variants[0]
        members = tuple(sorted((entry[0] for entry in entries), key=lambda food: (food.source, food.source_id)))
        reasons = sorted({entry[1].review_reason for entry in entries if entry[1].review_reason})
        calorie_spread = max(food.calories for food in members) - min(food.calories for food in members)
        if len(variants) > 20:
            reasons.append("more than 20 structured variants")
        if calorie_spread > 250:
            reasons.append("calorie spread exceeds 250 kcal/100 g")
        confidence = "review" if reasons else "high"
        aliases = " | ".join(dict.fromkeys(food.name for food in members))
        families.append(
            Family(
                family_id=family_id,
                family_key=family_key,
                title=entries[0][1].family_title,
                default_variant=default_variant,
                variants=tuple(variants),
                members=members,
                confidence=confidence,
                review_reason="; ".join(dict.fromkeys(reasons)),
                aliases=aliases,
            )
        )
    return sorted(families, key=lambda family: (family.title.casefold(), family.family_id))


def create_database(path: Path, source_path: Path, foods: list[Food], families: list[Family]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".partial")
    temporary.unlink(missing_ok=True)
    database = sqlite3.connect(temporary)
    try:
        database.executescript(
            """
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            PRAGMA temp_store=MEMORY;
            CREATE TABLE source_foods (
                source_rowid INTEGER NOT NULL,
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
                rank INTEGER NOT NULL DEFAULT 0,
                UNIQUE(source, source_id)
            );
            CREATE TABLE food_families (
                family_id TEXT PRIMARY KEY,
                family_key TEXT NOT NULL UNIQUE,
                canonical_name TEXT NOT NULL,
                default_variant_id TEXT NOT NULL,
                variant_count INTEGER NOT NULL,
                member_count INTEGER NOT NULL,
                confidence TEXT NOT NULL,
                review_reason TEXT NOT NULL,
                calorie_min REAL NOT NULL,
                calorie_max REAL NOT NULL
            );
            CREATE TABLE food_variants (
                variant_id TEXT PRIMARY KEY,
                family_id TEXT NOT NULL REFERENCES food_families(family_id),
                display_name TEXT NOT NULL,
                state TEXT NOT NULL,
                preparation TEXT NOT NULL,
                preservation TEXT NOT NULL,
                skin TEXT NOT NULL,
                coating TEXT NOT NULL,
                sauce TEXT NOT NULL,
                cooking_medium TEXT NOT NULL,
                additions TEXT NOT NULL,
                product_form TEXT NOT NULL,
                context TEXT NOT NULL,
                canonical_source TEXT NOT NULL,
                canonical_source_id TEXT NOT NULL,
                member_count INTEGER NOT NULL,
                is_default INTEGER NOT NULL
            );
            CREATE TABLE food_variant_members (
                variant_id TEXT NOT NULL REFERENCES food_variants(variant_id),
                family_id TEXT NOT NULL REFERENCES food_families(family_id),
                source TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_rowid INTEGER NOT NULL,
                original_name TEXT NOT NULL,
                is_canonical INTEGER NOT NULL,
                PRIMARY KEY (variant_id, source, source_id)
            );
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
                rank INTEGER NOT NULL DEFAULT 0,
                aliases TEXT NOT NULL,
                family_id TEXT NOT NULL UNIQUE,
                default_variant_id TEXT NOT NULL,
                UNIQUE(source, source_id)
            );
            CREATE TABLE variant_foods (
                variant_id TEXT PRIMARY KEY,
                family_id TEXT NOT NULL,
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
                rank INTEGER NOT NULL,
                aliases TEXT NOT NULL
            );
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE INDEX foods_source_rank ON foods(source, rank DESC);
            CREATE INDEX foods_barcode ON foods(barcode) WHERE barcode IS NOT NULL;
            CREATE INDEX food_variants_family ON food_variants(family_id, is_default DESC);
            CREATE INDEX food_variant_members_source ON food_variant_members(source, source_id);
            """
        )
        database.executemany(
            "INSERT INTO source_foods VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [tuple(food.__dict__.values()) for food in foods],
        )
        for family in families:
            database.execute(
                "INSERT INTO food_families VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    family.family_id,
                    family.family_key,
                    family.title,
                    family.default_variant.variant_id,
                    len(family.variants),
                    len(family.members),
                    family.confidence,
                    family.review_reason,
                    family.calorie_min,
                    family.calorie_max,
                ),
            )
            for variant in family.variants:
                identity = variant.identity
                database.execute(
                    "INSERT INTO food_variants VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        variant.variant_id,
                        family.family_id,
                        variant.title,
                        identity.state,
                        identity.preparation,
                        identity.preservation,
                        identity.skin,
                        identity.coating,
                        identity.sauce,
                        identity.cooking_medium,
                        identity.additions,
                        identity.product_form,
                        identity.context,
                        variant.canonical.source,
                        variant.canonical.source_id,
                        len(variant.members),
                        int(variant == family.default_variant),
                    ),
                )
                database.executemany(
                    "INSERT INTO food_variant_members VALUES (?, ?, ?, ?, ?, ?, ?)",
                    [
                        (
                            variant.variant_id,
                            family.family_id,
                            member.source,
                            member.source_id,
                            member.rowid,
                            member.name,
                            int(member == variant.canonical),
                        )
                        for member in variant.members
                    ],
                )
                canonical = variant.canonical
                aliases = " | ".join(dict.fromkeys(member.name for member in variant.members))
                database.execute(
                    "INSERT INTO variant_foods VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        variant.variant_id,
                        family.family_id,
                        canonical.source_id,
                        canonical.source,
                        variant.title,
                        canonical.brand,
                        canonical.barcode,
                        canonical.calories,
                        canonical.carbs,
                        canonical.fat,
                        canonical.protein,
                        canonical.fiber,
                        canonical.base_grams,
                        canonical.serving_grams,
                        canonical.serving_description,
                        canonical.portions_json,
                        canonical.rank + (1_000_000 if identity.context == "generic" else 0),
                        aliases,
                    ),
                )
            canonical = family.default_variant.canonical
            family_rank = canonical.rank + (
                1_000_000 if family.default_variant.identity.context == "generic" else 0
            )
            database.execute(
                "INSERT INTO foods VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    canonical.source_id,
                    canonical.source,
                    family.title,
                    canonical.brand,
                    canonical.barcode,
                    canonical.calories,
                    canonical.carbs,
                    canonical.fat,
                    canonical.protein,
                    canonical.fiber,
                    canonical.base_grams,
                    canonical.serving_grams,
                    canonical.serving_description,
                    canonical.portions_json,
                    family_rank,
                    family.aliases,
                    family.family_id,
                    family.default_variant.variant_id,
                ),
            )
        database.executescript(
            """
            CREATE VIRTUAL TABLE foods_fts USING fts5(
                name, brand, aliases, content='foods', content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            );
            INSERT INTO foods_fts(rowid, name, brand, aliases)
                SELECT rowid,
                       CASE WHEN name = 'Egg' THEN 'Egg whole' ELSE name END,
                       coalesce(brand, ''), ''
                FROM foods;
            CREATE VIRTUAL TABLE variant_foods_fts USING fts5(
                name, brand, aliases, content='variant_foods', content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            );
            INSERT INTO variant_foods_fts(rowid, name, brand, aliases)
                SELECT v.rowid,
                       CASE WHEN f.canonical_name = 'Egg'
                            THEN 'Egg whole' || substr(v.name, 4)
                            ELSE v.name END,
                       coalesce(v.brand, ''), v.aliases
                FROM variant_foods v
                JOIN food_families f ON f.family_id = v.family_id;
            """
        )
        metadata = {
            "schema_version": "family-variant-2",
            "identity_algorithm_version": ALGORITHM_VERSION,
            "source_catalog": str(source_path.resolve()),
            "source_food_count": str(len(foods)),
            "family_count": str(len(families)),
            "variant_count": str(sum(len(family.variants) for family in families)),
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "search_modes": "foods_fts=one default per family; variant_foods_fts=one row per structured variant",
            "warning": "Experimental entity resolution; review flagged families before production use.",
        }
        database.executemany("INSERT INTO metadata VALUES (?, ?)", metadata.items())
        database.executescript("ANALYZE; VACUUM;")
        if database.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("SQLite integrity check failed")
    except Exception:
        database.close()
        temporary.unlink(missing_ok=True)
        raise
    else:
        database.close()
    shutil.move(temporary, path)


def fts_search(path: Path, table: str, content_table: str, query: str, limit: int = 5) -> tuple[int, list[str]]:
    if table not in {"foods_fts", "variant_foods_fts"} or content_table not in {"foods", "variant_foods"}:
        raise ValueError("Unexpected search table")
    terms = " ".join(f"{token}*" for token in normalized_text(query).split()[:8])
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    try:
        count = database.execute(f"SELECT count(*) FROM {table} WHERE {table} MATCH ?", (terms,)).fetchone()[0]
        names = [
            row[0]
            for row in database.execute(
                f"""
                SELECT f.name FROM {table}
                JOIN {content_table} f ON f.rowid = {table}.rowid
                WHERE {table} MATCH ?
                ORDER BY CASE
                    WHEN lower(f.name) = lower(?) THEN 0
                    WHEN lower(f.name) LIKE lower(?) || ',%' THEN 1
                    WHEN lower(f.name) LIKE lower(?) || '%' THEN 2
                    ELSE 3 END,
                    bm25({table}, 8.0, 3.0), length(f.name), f.rank DESC
                LIMIT ?
                """,
                (terms, query, query, query, limit),
            )
        ]
    finally:
        database.close()
    return count, names


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def family_row(family: Family, include_variants: bool = False) -> str:
    details = ""
    if include_variants:
        items = "".join(
            f"<li><strong>{esc(variant.title)}</strong> — {variant.canonical.calories:.0f} kcal/100 g"
            f" <span>{len(variant.members)} source record{'s' if len(variant.members) != 1 else ''}"
            f"{' · default' if variant == family.default_variant else ''}</span></li>"
            for variant in family.variants
        )
        details = f"<details><summary>Show {len(family.variants)} variants</summary><ul>{items}</ul></details>"
    return (
        f"<tr data-search=\"{esc(family.title + ' ' + family.aliases)}\">"
        f"<td><strong>{esc(family.title)}</strong>{details}</td>"
        f"<td>{len(family.variants):,}</td><td>{len(family.members):,}</td>"
        f"<td>{esc(family.default_variant.title)}<small>{esc(family.default_variant.canonical.name)} · "
        f"{family.default_variant.canonical.calories:.0f} kcal/100 g</small></td>"
        f"<td>{family.calorie_min:.0f}–{family.calorie_max:.0f}</td>"
        f"<td>{esc(family.confidence)}<small>{esc(family.review_reason)}</small></td></tr>"
    )


def render_report(source_path: Path, output_path: Path, foods: list[Food], families: list[Family]) -> str:
    variants = [variant for family in families for variant in family.variants]
    reduction = len(foods) - len(families)
    review = [family for family in families if family.confidence == "review"]
    largest = sorted(families, key=lambda family: (-len(family.members), family.title.casefold()))[:35]
    widest = sorted(
        (family for family in families if len(family.members) > 1),
        key=lambda family: (-(family.calorie_max - family.calorie_min), -len(family.members)),
    )[:30]
    examples = [
        family
        for family in families
        if family.title.casefold() in {
            "chicken breast",
            "egg omelet",
            "egg",
            "egg, white",
            "egg, yolk",
        }
    ]
    examples.sort(key=lambda family: family.title.casefold())
    searches = []
    for query in REPORT_SEARCHES:
        original = catalog_search(source_path, query)
        family = fts_search(output_path, "foods_fts", "foods", query)
        variant = fts_search(output_path, "variant_foods_fts", "variant_foods", query)
        searches.append((query, original, family, variant))

    search_rows = "".join(
        "<tr>"
        f"<td><strong>{esc(query)}</strong></td>"
        f"<td>{original[0]:,}<small>{esc(' · '.join(original[1]))}</small></td>"
        f"<td>{family[0]:,}<small>{esc(' · '.join(family[1]))}</small></td>"
        f"<td>{variant[0]:,}<small>{esc(' · '.join(variant[1]))}</small></td>"
        f"<td>{100 * (original[0] - family[0]) / original[0]:.1f}%</td></tr>"
        for query, original, family, variant in searches
    )
    generated = dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Food family identity catalog</title>
<style>
:root {{ color-scheme:light dark;--bg:#f2f0e8;--panel:#fffdf7;--ink:#25231f;--muted:#746f64;--line:#dcd5c7;--family:#375e8d;--variant:#a15c2f;--ok:#39745a;--warn:#a04338 }}
@media(prefers-color-scheme:dark) {{ :root{{--bg:#161713;--panel:#20221d;--ink:#f2efe6;--muted:#aaa497;--line:#3d4037;--family:#7fa9dc;--variant:#e1915c;--ok:#70b18e;--warn:#ed8d82}} }}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}} main{{max-width:1220px;margin:auto;padding:44px 24px 80px}}
h1{{font:700 clamp(36px,6vw,68px)/.98 ui-serif,Georgia,serif;letter-spacing:-.04em;max-width:940px;margin:0 0 16px}} h2{{font:700 28px/1.15 ui-serif,Georgia,serif;margin:48px 0 13px}} h3{{margin:0 0 8px}} p{{max-width:900px}} .stamp,.muted,small{{color:var(--muted)}} .lede{{font-size:18px;color:var(--muted)}}
.metrics{{display:grid;grid-template-columns:repeat(5,1fr);gap:11px;margin:28px 0}} .metric,.panel{{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:17px}} .metric b{{display:block;font:700 29px/1 ui-serif,Georgia,serif;color:var(--family)}} .metric span{{color:var(--muted)}}
.flow{{display:grid;grid-template-columns:1fr auto 1fr auto 1fr;gap:12px;align-items:center;margin:22px 0}} .flow .panel{{text-align:center}} .flow b{{display:block;font-size:23px}} .arrow{{font-size:24px;color:var(--muted)}}
.note{{border-left:4px solid var(--warn);padding:12px 15px;background:color-mix(in srgb,var(--warn) 8%,var(--panel));margin:18px 0}} .two{{display:grid;grid-template-columns:1fr 1fr;gap:14px}}
.table-wrap{{overflow:auto;background:var(--panel);border:1px solid var(--line);border-radius:14px}} table{{border-collapse:collapse;width:100%}} th,td{{padding:11px 13px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}} th{{position:sticky;top:0;background:var(--panel);font-size:12px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted)}} tr:last-child td{{border:0}} td small{{display:block}}
details{{margin-top:5px}} summary{{cursor:pointer;color:var(--family)}} ul{{margin:8px 0;padding-left:20px}} li span{{color:var(--muted);font-size:12px}} input{{width:100%;padding:11px 13px;margin-bottom:10px;border:1px solid var(--line);border-radius:10px;background:var(--panel);color:var(--ink);font:inherit}} code{{font-size:12px}} .schema{{white-space:pre-wrap;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--muted)}}
@media(max-width:850px){{.metrics{{grid-template-columns:1fr 1fr}}.flow{{grid-template-columns:1fr}}.arrow{{transform:rotate(90deg);text-align:center}}.two{{grid-template-columns:1fr}}main{{padding:28px 14px 60px}}}}
</style></head><body><main>
<p class="stamp">ENTITY-RESOLUTION EXPERIMENT · {esc(generated)}</p>
<h1>Search the food. Resolve the preparation only when it matters.</h1>
<p class="lede">The catalog now models a canonical food family separately from nutritional variants and source records. Family-level search can return one “Chicken breast” or “Egg, whole” result, while a preparation-aware path can resolve raw, roasted, fried, dried, skin-on, or other variants.</p>
<section class="metrics"><div class="metric"><b>{len(foods):,}</b><span>source records</span></div><div class="metric"><b>{len(families):,}</b><span>food families</span></div><div class="metric"><b>{len(variants):,}</b><span>structured variants</span></div><div class="metric"><b>{reduction:,}</b><span>fewer family rows</span></div><div class="metric"><b>{len(review):,}</b><span>families flagged</span></div></section>
<div class="flow"><div class="panel"><b>{len(families):,}</b>canonical families<small>future default search surface</small></div><div class="arrow">→</div><div class="panel"><b>{len(variants):,}</b>nutrition-bearing variants<small>selected by explicit query intent or disclosure</small></div><div class="arrow">→</div><div class="panel"><b>{len(foods):,}</b>source records<small>fully retained for audit and provenance</small></div></div>
<div class="note"><strong>Safety boundary:</strong> the family owns the searchable identity; the default variant owns the displayed nutrition. Nutrition is never averaged across raw, cooked, skin-on, coated, dried, or restaurant variants.</div>

<h2>Search-result impact</h2><p>Family mode returns one default row per family. Variant mode returns one row per structured nutritional variant and is useful when the query names a preparation.</p>
<div class="table-wrap"><table><thead><tr><th>Query</th><th>Original records</th><th>Family mode</th><th>Variant mode</th><th>Family reduction</th></tr></thead><tbody>{search_rows}</tbody></table></div>

<h2>Chicken and egg identities</h2><p>These examples show the proposed future interaction: a compact family result backed by an explicit default and expandable preparation variants.</p>
<div class="table-wrap"><table><thead><tr><th>Family</th><th>Variants</th><th>Records</th><th>Default variant and record</th><th>kcal range</th><th>Confidence</th></tr></thead><tbody>{''.join(family_row(family, True) for family in examples)}</tbody></table></div>

<h2>Largest families</h2><input id="family-filter" type="search" placeholder="Filter families, variants, or source titles…" aria-label="Filter families">
<div class="table-wrap"><table id="family-table"><thead><tr><th>Family</th><th>Variants</th><th>Records</th><th>Default variant and record</th><th>kcal range</th><th>Confidence</th></tr></thead><tbody>{''.join(family_row(family, True) for family in largest)}</tbody></table></div>

<h2>Highest-review families</h2><p>Wide calorie ranges are expected when a family legitimately contains dry/raw and prepared variants. These are review priorities for default selection and variant labels—not candidates for nutritional averaging.</p>
<div class="table-wrap"><table><thead><tr><th>Family</th><th>Variants</th><th>Records</th><th>Default variant and record</th><th>kcal range</th><th>Confidence</th></tr></thead><tbody>{''.join(family_row(family, True) for family in widest)}</tbody></table></div>

<h2>Recommended search behavior</h2><div class="two"><section class="panel"><h3>Generic query</h3><p>“Chicken breast” returns the family once using its default cooked, neutral variant. A disclosure reveals the variant list.</p></section><section class="panel"><h3>Preparation query</h3><p>“Raw chicken breast” or “fried egg” routes through the variant index and selects the matching structured variant directly.</p></section></div>

<h2>Database topology</h2><pre class="panel schema">foods + foods_fts ({len(families):,} family-level default rows)
└── food_families ({len(families):,})
    └── food_variants ({len(variants):,})
        ├── variant_foods + variant_foods_fts ({len(variants):,})
        └── food_variant_members ({len(foods):,})
            └── source_foods ({len(foods):,})

Input:  {esc(source_path.resolve())} · {esc(file_size_mib(source_path))}
Output: {esc(output_path.resolve())} · {esc(file_size_mib(output_path))}</pre>
</main><script>const input=document.getElementById('family-filter');const rows=[...document.querySelectorAll('#family-table tbody tr')];input.addEventListener('input',()=>{{const q=input.value.trim().toLocaleLowerCase();for(const row of rows)row.hidden=q&&!row.dataset.search.toLocaleLowerCase().includes(q)}});</script></body></html>"""


def validate_database(path: Path, source_count: int, families: list[Family]) -> None:
    variant_count = sum(len(family.variants) for family in families)
    expected = {
        "source_foods": source_count,
        "food_variant_members": source_count,
        "food_families": len(families),
        "foods": len(families),
        "foods_fts": len(families),
        "food_variants": variant_count,
        "variant_foods": variant_count,
        "variant_foods_fts": variant_count,
    }
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    try:
        for table, count in expected.items():
            actual = database.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            if actual != count:
                raise RuntimeError(f"{table} has {actual:,} rows; expected {count:,}")
        missing = database.execute(
            """
            SELECT count(*) FROM source_foods s LEFT JOIN food_variant_members m
              ON m.source=s.source AND m.source_id=s.source_id
            WHERE m.variant_id IS NULL
            """
        ).fetchone()[0]
        if missing:
            raise RuntimeError(f"{missing} source rows are missing variant membership")
        invalid_defaults = database.execute(
            """
            SELECT count(*) FROM food_families f
            LEFT JOIN food_variants v ON v.variant_id=f.default_variant_id
            WHERE v.family_id IS NOT f.family_id OR v.is_default != 1
            """
        ).fetchone()[0]
        if invalid_defaults:
            raise RuntimeError(f"{invalid_defaults} families have invalid defaults")
        if database.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("Final SQLite integrity check failed")
    finally:
        database.close()


def main() -> int:
    arguments = parse_args()
    foods = read_foods(arguments.input)
    families = build_families(foods)
    create_database(arguments.output, arguments.input, foods, families)
    validate_database(arguments.output, len(foods), families)
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        render_report(arguments.input, arguments.output, foods, families),
        encoding="utf-8",
    )
    variants = sum(len(family.variants) for family in families)
    print(f"Source records: {len(foods):,}")
    print(f"Food families: {len(families):,}")
    print(f"Structured variants: {variants:,}")
    print(f"Wrote family catalog to {arguments.output.resolve()}")
    print(f"Wrote HTML report to {arguments.report.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
