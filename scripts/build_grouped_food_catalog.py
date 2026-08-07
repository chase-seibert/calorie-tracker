#!/usr/bin/env python3
"""Build an experimental food catalog with canonical similarity groups.

The input catalog is never modified. The output keeps every original row in
``source_foods`` while exposing one representative row per group through the
app-compatible ``foods`` table. Group aliases remain searchable through the
third column of ``foods_fts``.

This is deliberately a reviewable heuristic, not a claim that differently
prepared foods have interchangeable nutrition. The generated HTML report calls
out groups with broad calorie or macro ranges before the database is considered
for production use.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import math
import re
import shutil
import sqlite3
import statistics
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "CalorieTracker" / "Resources" / "FoodCatalog.sqlite3"
DEFAULT_OUTPUT = ROOT / "data" / "work" / "catalogs" / "grouped-food-catalog.sqlite3"
DEFAULT_REPORT = ROOT / "data" / "work" / "catalog-reports" / "grouped-food-catalog.html"
ALGORITHM_VERSION = "1"

# These describe preparation or presentation rather than the underlying food.
# Removing them creates a family; every original title remains in the member
# table and FTS aliases so specific searches such as "chicken breast stewed"
# still resolve to the family.
PREPARATION_TOKENS = {
    "baked",
    "boiled",
    "braised",
    "broiled",
    "canned",
    "coated",
    "cooked",
    "cooking",
    "drained",
    "fried",
    "frozen",
    "grilled",
    "heated",
    "microwaved",
    "oven",
    "poached",
    "precooked",
    "prepared",
    "raw",
    "roasted",
    "sauteed",
    "simmered",
    "sliced",
    "steamed",
    "stewed",
    "toasted",
    "unheated",
}
PREPARATION_CONNECTORS = {"and", "or"}
POULTRY_DETAIL_TOKENS = {
    "added",
    "batter",
    "bbq",
    "boneless",
    "breaded",
    "breading",
    "broiler",
    "broilers",
    "coating",
    "fast",
    "flour",
    "food",
    "from",
    "fryer",
    "fryers",
    "marinade",
    "marinated",
    "meat",
    "not",
    "only",
    "original",
    "restaurant",
    "rotisserie",
    "seasoning",
    "skinless",
    "sauce",
    "solution",
    "to",
    "with",
    "without",
}
GENERIC_POULTRY_TOKENS = {"chicken", "turkey", "duck", "goose"}
POULTRY_BODY_PARTS = {"back", "breast", "dark", "drumstick", "leg", "light", "neck", "thigh", "wing"}
RESTAURANT_OR_BRAND_MARKERS = {
    "arbys",
    "burger king",
    "campbells",
    "chick fil a",
    "dennys",
    "dominos",
    "fast foods",
    "kfc",
    "mcdonalds",
    "oscar mayer",
    "papa johns",
    "pizza hut",
    "popeyes",
    "subway",
    "taco bell",
    "wendys",
}
HIGH_VARIATION_MARKERS = {
    "batter",
    "breaded",
    "coated",
    "fried",
    "marinade",
    "marinated",
    "restaurant",
    "sauce",
    "stuffed",
}
REPORT_SEARCHES = ("chicken breast", "egg", "salmon", "rice", "milk", "butter")


@dataclass(frozen=True)
class Food:
    rowid: int
    source_id: str
    source: str
    name: str
    brand: str | None
    barcode: str | None
    calories: float
    carbs: float
    fat: float
    protein: float
    base_grams: float
    serving_grams: float | None
    serving_description: str | None
    portions_json: str | None
    rank: int


@dataclass(frozen=True)
class Group:
    group_id: str
    group_key: str
    canonical_title: str
    canonical: Food
    members: tuple[Food, ...]
    method: str
    confidence: str
    calorie_min: float
    calorie_max: float
    protein_min: float
    protein_max: float
    fat_min: float
    fat_max: float
    carbs_min: float
    carbs_max: float
    aliases: str

    @property
    def calorie_spread(self) -> float:
        return self.calorie_max - self.calorie_min


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def normalized_text(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    ascii_value = ascii_value.lower().replace("&", " and ")
    ascii_value = re.sub(r"\bpre[ -]?cooked\b", " precooked ", ascii_value)
    ascii_value = re.sub(r"\bns as to cooking method\b", " ", ascii_value)
    ascii_value = re.sub(r"\bbroilers? or fryers?\b", " ", ascii_value)
    return " ".join(re.findall(r"[a-z0-9]+", ascii_value))


def is_explicit_brand_or_restaurant(food: Food, normalized_name: str) -> bool:
    if food.brand:
        return True
    return any(marker in normalized_name for marker in RESTAURANT_OR_BRAND_MARKERS)


def family_identity(food: Food) -> tuple[str, tuple[str, ...], bool]:
    normalized_name = normalized_text(food.name)
    if food.source != "usda" or is_explicit_brand_or_restaurant(food, normalized_name):
        brand = normalized_text(food.brand or "")
        key = f"{food.source}|product|{brand}|{normalized_name}"
        return key, tuple(normalized_name.split()), False

    tokens = normalized_name.split()
    removable = set(PREPARATION_TOKENS) | PREPARATION_CONNECTORS
    if any(token in GENERIC_POULTRY_TOKENS for token in tokens):
        removable |= POULTRY_DETAIL_TOKENS
        if "meat" in tokens or any(token in POULTRY_BODY_PARTS for token in tokens):
            removable |= {"eaten", "skin"}
    core_tokens = tuple(token for token in tokens if token not in removable)
    if not core_tokens:
        core_tokens = tuple(tokens)
    changed = core_tokens != tuple(tokens)
    return f"usda|generic|{' '.join(core_tokens)}", core_tokens, changed


def humanized_title(core_tokens: tuple[str, ...], fallback: str) -> str:
    if not core_tokens:
        return fallback
    title = " ".join(core_tokens)
    return title[:1].upper() + title[1:]


def nutrition_distance(food: Food, members: Iterable[Food]) -> float:
    rows = tuple(members)
    medians = (
        statistics.median(row.calories for row in rows),
        statistics.median(row.carbs for row in rows),
        statistics.median(row.fat for row in rows),
        statistics.median(row.protein for row in rows),
    )
    values = (food.calories, food.carbs, food.fat, food.protein)
    scales = (max(medians[0], 50), max(medians[1], 10), max(medians[2], 5), max(medians[3], 10))
    return sum(abs(value - median) / scale for value, median, scale in zip(values, medians, scales))


def representative_penalty(food: Food) -> int:
    name = normalized_text(food.name)
    tokens = set(name.split())
    penalty = 0
    penalty += 12 * len(tokens & HIGH_VARIATION_MARKERS)
    penalty += 8 if "fast food" in name else 0
    penalty += 6 if "skin eaten" in name or "meat and skin" in name else 0
    penalty += 4 if "raw" in tokens else 0
    penalty += 3 if "canned" in tokens else 0
    penalty += 2 if "frozen" in tokens else 0
    penalty += 3 if "ns as to" in name else 0
    penalty -= 3 if "skin not eaten" in name or "skinless" in tokens or "meat only" in name else 0
    penalty -= 2 if tokens & {"baked", "broiled", "grilled", "roasted"} else 0
    return penalty


def canonical_food(members: tuple[Food, ...]) -> Food:
    return min(
        members,
        key=lambda food: (
            representative_penalty(food),
            round(nutrition_distance(food, members), 6),
            -food.rank,
            0 if food.serving_grams else 1,
            len(food.name),
            food.source_id,
        ),
    )


def build_groups(foods: list[Food]) -> list[Group]:
    buckets: dict[str, list[tuple[Food, tuple[str, ...], bool]]] = defaultdict(list)
    for food in foods:
        key, core_tokens, changed = family_identity(food)
        buckets[key].append((food, core_tokens, changed))

    groups: list[Group] = []
    for key, entries in buckets.items():
        members = tuple(sorted((entry[0] for entry in entries), key=lambda row: (row.source, row.source_id)))
        representative = canonical_food(members)
        has_family_normalization = any(entry[2] for entry in entries)
        if len(members) == 1:
            method = "singleton"
            confidence = "source row"
        elif has_family_normalization:
            method = "preparation family"
            confidence = "review recommended"
        else:
            method = "exact product/title"
            confidence = "high"

        if has_family_normalization:
            canonical_title = humanized_title(entries[0][1], representative.name)
        else:
            canonical_title = representative.name
        aliases = " | ".join(
            dict.fromkeys(
                value
                for member in members
                for value in (member.name, member.brand)
                if value
            )
        )
        digest = hashlib.sha1(key.encode("utf-8"), usedforsecurity=False).hexdigest()[:16]
        groups.append(
            Group(
                group_id=f"grp-{digest}",
                group_key=key,
                canonical_title=canonical_title,
                canonical=representative,
                members=members,
                method=method,
                confidence=confidence,
                calorie_min=min(row.calories for row in members),
                calorie_max=max(row.calories for row in members),
                protein_min=min(row.protein for row in members),
                protein_max=max(row.protein for row in members),
                fat_min=min(row.fat for row in members),
                fat_max=max(row.fat for row in members),
                carbs_min=min(row.carbs for row in members),
                carbs_max=max(row.carbs for row in members),
                aliases=aliases,
            )
        )
    return sorted(groups, key=lambda group: (group.canonical_title.casefold(), group.group_id))


def read_foods(path: Path) -> list[Food]:
    if not path.is_file():
        raise FileNotFoundError(path)
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    try:
        rows = database.execute(
            """
            SELECT rowid, source_id, source, name, brand, barcode, calories,
                   carbs, fat, protein, base_grams, serving_grams,
                   serving_description, portions_json, rank
            FROM foods ORDER BY rowid
            """
        ).fetchall()
    finally:
        database.close()
    return [Food(*row) for row in rows]


def create_database(path: Path, source_path: Path, foods: list[Food], groups: list[Group]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".partial")
    if temporary.exists():
        temporary.unlink()
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
                base_grams REAL NOT NULL,
                serving_grams REAL,
                serving_description TEXT,
                portions_json TEXT,
                rank INTEGER NOT NULL DEFAULT 0,
                UNIQUE(source, source_id)
            );
            CREATE TABLE food_groups (
                group_id TEXT PRIMARY KEY,
                group_key TEXT NOT NULL UNIQUE,
                canonical_title TEXT NOT NULL,
                canonical_source TEXT NOT NULL,
                canonical_source_id TEXT NOT NULL,
                canonical_record_name TEXT NOT NULL,
                member_count INTEGER NOT NULL,
                grouping_method TEXT NOT NULL,
                confidence TEXT NOT NULL,
                calorie_min REAL NOT NULL,
                calorie_max REAL NOT NULL,
                protein_min REAL NOT NULL,
                protein_max REAL NOT NULL,
                fat_min REAL NOT NULL,
                fat_max REAL NOT NULL,
                carbs_min REAL NOT NULL,
                carbs_max REAL NOT NULL
            );
            CREATE TABLE food_group_members (
                group_id TEXT NOT NULL REFERENCES food_groups(group_id),
                source TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_rowid INTEGER NOT NULL,
                original_name TEXT NOT NULL,
                is_canonical INTEGER NOT NULL,
                PRIMARY KEY (group_id, source, source_id)
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
                base_grams REAL NOT NULL,
                serving_grams REAL,
                serving_description TEXT,
                portions_json TEXT,
                rank INTEGER NOT NULL DEFAULT 0,
                aliases TEXT NOT NULL,
                group_id TEXT NOT NULL UNIQUE,
                UNIQUE(source, source_id)
            );
            CREATE INDEX foods_source_rank ON foods(source, rank DESC);
            CREATE INDEX foods_barcode ON foods(barcode) WHERE barcode IS NOT NULL;
            CREATE INDEX food_group_members_source ON food_group_members(source, source_id);
            CREATE INDEX food_group_members_group ON food_group_members(group_id);
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """
        )
        database.executemany(
            "INSERT INTO source_foods VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [tuple(food.__dict__.values()) for food in foods],
        )
        for group in groups:
            database.execute(
                "INSERT INTO food_groups VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    group.group_id,
                    group.group_key,
                    group.canonical_title,
                    group.canonical.source,
                    group.canonical.source_id,
                    group.canonical.name,
                    len(group.members),
                    group.method,
                    group.confidence,
                    group.calorie_min,
                    group.calorie_max,
                    group.protein_min,
                    group.protein_max,
                    group.fat_min,
                    group.fat_max,
                    group.carbs_min,
                    group.carbs_max,
                ),
            )
            database.executemany(
                "INSERT INTO food_group_members VALUES (?, ?, ?, ?, ?, ?)",
                [
                    (
                        group.group_id,
                        member.source,
                        member.source_id,
                        member.rowid,
                        member.name,
                        int(member == group.canonical),
                    )
                    for member in group.members
                ],
            )
            canonical = group.canonical
            database.execute(
                "INSERT INTO foods VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    canonical.source_id,
                    canonical.source,
                    group.canonical_title,
                    canonical.brand,
                    canonical.barcode,
                    canonical.calories,
                    canonical.carbs,
                    canonical.fat,
                    canonical.protein,
                    canonical.base_grams,
                    canonical.serving_grams,
                    canonical.serving_description,
                    canonical.portions_json,
                    canonical.rank,
                    group.aliases,
                    group.group_id,
                ),
            )
        database.executescript(
            """
            CREATE VIRTUAL TABLE foods_fts USING fts5(
                name,
                brand,
                aliases,
                content='foods',
                content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            );
            INSERT INTO foods_fts(rowid, name, brand, aliases)
                SELECT rowid, name, coalesce(brand, ''), aliases FROM foods;
            """
        )
        metadata = {
            "schema_version": "grouped-1",
            "grouping_algorithm_version": ALGORITHM_VERSION,
            "source_catalog": str(source_path.resolve()),
            "source_food_count": str(len(foods)),
            "canonical_food_count": str(len(groups)),
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "warning": "Experimental heuristic groups; review preparation families and nutrient spreads before production use.",
        }
        database.executemany("INSERT INTO metadata VALUES (?, ?)", metadata.items())
        database.executescript("ANALYZE; VACUUM;")
        integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"SQLite integrity check failed: {integrity}")
    except Exception:
        database.close()
        temporary.unlink(missing_ok=True)
        raise
    else:
        database.close()
    shutil.move(temporary, path)


def fmt(value: float, digits: int = 0) -> str:
    return f"{value:,.{digits}f}"


def file_size_mib(path: Path) -> str:
    return f"{path.stat().st_size / 1024 / 1024:.1f} MiB"


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def group_row(group: Group, include_members: bool = False) -> str:
    members = ""
    if include_members:
        members = "<details><summary>Show members</summary><ul>" + "".join(
            f"<li>{esc(member.name)} <span>{esc(member.source.upper())} · {esc(member.source_id)}</span></li>"
            for member in sorted(group.members, key=lambda row: row.name.casefold())
        ) + "</ul></details>"
    return (
        f"<tr data-search=\"{esc(group.canonical_title + ' ' + group.aliases)}\">"
        f"<td><strong>{esc(group.canonical_title)}</strong>{members}</td>"
        f"<td>{len(group.members):,}</td>"
        f"<td>{esc(group.canonical.name)}<small>{esc(group.canonical.source.upper())} · {esc(group.canonical.source_id)}</small></td>"
        f"<td>{fmt(group.calorie_min)}–{fmt(group.calorie_max)}</td>"
        f"<td>{fmt(group.protein_min, 1)}–{fmt(group.protein_max, 1)}</td>"
        f"<td>{esc(group.method)}</td>"
        "</tr>"
    )


def catalog_search(path: Path, query: str, limit: int = 5) -> tuple[int, list[str]]:
    terms = " ".join(f"{token}*" for token in normalized_text(query).split()[:8])
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    try:
        count = database.execute(
            "SELECT count(*) FROM foods_fts WHERE foods_fts MATCH ?",
            (terms,),
        ).fetchone()[0]
        rows = database.execute(
            """
            SELECT f.name
            FROM foods_fts JOIN foods f ON f.rowid = foods_fts.rowid
            WHERE foods_fts MATCH ?
            ORDER BY
                CASE
                    WHEN lower(f.name) = lower(?) THEN 0
                    WHEN lower(f.name) LIKE lower(?) || ',%' THEN 1
                    WHEN lower(f.name) LIKE lower(?) || '%' THEN 2
                    ELSE 3
                END,
                bm25(foods_fts, 8.0, 3.0), length(f.name), f.rank DESC
            LIMIT ?
            """,
            (terms, query, query, query, limit),
        ).fetchall()
    finally:
        database.close()
    return count, [row[0] for row in rows]


def render_report(source_path: Path, output_path: Path, foods: list[Food], groups: list[Group]) -> str:
    grouped = [group for group in groups if len(group.members) > 1]
    family_groups = [group for group in grouped if group.method == "preparation family"]
    exact_groups = [group for group in grouped if group.method == "exact product/title"]
    reduction = len(foods) - len(groups)
    reduction_percent = 100 * reduction / len(foods)
    size_counts = Counter(
        "1" if len(group.members) == 1 else "2" if len(group.members) == 2 else "3–5" if len(group.members) <= 5 else "6–10" if len(group.members) <= 10 else "11+"
        for group in groups
    )
    size_order = ["1", "2", "3–5", "6–10", "11+"]
    largest = sorted(grouped, key=lambda group: (-len(group.members), group.canonical_title.casefold()))[:30]
    widest = sorted(family_groups, key=lambda group: (-group.calorie_spread, -len(group.members)))[:30]
    chicken = [
        group
        for group in groups
        if "chicken" in normalized_text(group.canonical_title) and "breast" in normalized_text(group.canonical_title)
    ]
    chicken.sort(key=lambda group: (-len(group.members), group.canonical_title.casefold()))
    source_counts = Counter(food.source for food in foods)
    canonical_source_counts = Counter(group.canonical.source for group in groups)
    max_bucket = max(size_counts.values())
    search_comparisons = [
        (query, catalog_search(source_path, query), catalog_search(output_path, query))
        for query in REPORT_SEARCHES
    ]

    bucket_bars = "".join(
        f"<div class=\"bar-row\"><span>{esc(bucket)} members</span><div><i style=\"width:{100 * size_counts[bucket] / max_bucket:.2f}%\"></i></div><b>{size_counts[bucket]:,}</b></div>"
        for bucket in size_order
    )
    method_rows = "".join(
        f"<tr><td>{esc(method)}</td><td>{count:,}</td></tr>"
        for method, count in [
            ("Singleton source rows", len(groups) - len(grouped)),
            ("Exact product/title groups", len(exact_groups)),
            ("Preparation families", len(family_groups)),
        ]
    )
    search_rows = "".join(
        "<tr>"
        f"<td><strong>{esc(query)}</strong></td>"
        f"<td>{before_count:,}<small>{esc(' · '.join(before_names))}</small></td>"
        f"<td>{after_count:,}<small>{esc(' · '.join(after_names))}</small></td>"
        f"<td>{100 * (before_count - after_count) / before_count:.1f}%</td>"
        "</tr>"
        for query, (before_count, before_names), (after_count, after_names) in search_comparisons
    )
    generated = dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    report = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Grouped food catalog findings</title>
<style>
:root {{ color-scheme: light dark; --bg:#f4f1ea; --panel:#fffdf8; --ink:#26231d; --muted:#746d61; --line:#ddd5c7; --accent:#c85b32; --accent2:#477c69; --warn:#a73f32; }}
@media (prefers-color-scheme:dark) {{ :root {{ --bg:#171612; --panel:#211f1a; --ink:#f4eee4; --muted:#aaa092; --line:#403b33; --accent:#ee825b; --accent2:#70ad95; --warn:#f08b7e; }} }}
* {{ box-sizing:border-box }} body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif }}
main {{ max-width:1180px; margin:auto; padding:42px 24px 80px }} h1 {{ font:700 clamp(34px,6vw,66px)/.98 ui-serif,Georgia,serif; max-width:850px; margin:0 0 16px; letter-spacing:-.035em }}
.lede {{ font-size:18px; max-width:820px; color:var(--muted); margin-bottom:30px }} .stamp {{ color:var(--muted); font-size:13px }}
.grid {{ display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin:28px 0 }} .metric,.panel {{ background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:18px }}
.metric b {{ display:block; font:700 30px/1 ui-serif,Georgia,serif; color:var(--accent) }} .metric span,small {{ color:var(--muted) }}
h2 {{ font:700 28px/1.15 ui-serif,Georgia,serif; margin:46px 0 14px }} h3 {{ margin:0 0 10px }} .two {{ display:grid;grid-template-columns:1fr 1fr;gap:16px }}
.bar-row {{ display:grid;grid-template-columns:90px 1fr 65px;gap:10px;align-items:center;margin:10px 0 }} .bar-row div {{ height:12px;background:color-mix(in srgb,var(--line) 55%,transparent);border-radius:8px;overflow:hidden }} .bar-row i {{ display:block;height:100%;background:var(--accent2);border-radius:8px }}
.note {{ border-left:4px solid var(--warn); padding:12px 16px; background:color-mix(in srgb,var(--warn) 8%,var(--panel)); margin:18px 0 }}
.table-wrap {{ overflow:auto; border:1px solid var(--line);border-radius:14px;background:var(--panel) }} table {{ width:100%;border-collapse:collapse }} th,td {{ text-align:left;padding:11px 13px;border-bottom:1px solid var(--line);vertical-align:top }} th {{ position:sticky;top:0;background:var(--panel);font-size:12px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted) }} td small {{ display:block }} tr:last-child td {{ border:0 }}
input {{ width:100%;font:inherit;padding:11px 13px;margin:0 0 10px;border:1px solid var(--line);border-radius:10px;background:var(--panel);color:var(--ink) }}
details {{ margin-top:5px }} summary {{ color:var(--accent2);cursor:pointer }} ul {{ margin:8px 0;padding-left:20px }} li span {{ color:var(--muted);font-size:12px }} code {{ font-size:12px }}
.schema {{ white-space:pre-wrap;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--muted) }}
@media(max-width:780px) {{ .grid {{ grid-template-columns:1fr 1fr }} .two {{ grid-template-columns:1fr }} main {{ padding:28px 14px 60px }} }}
</style>
</head>
<body><main>
<p class="stamp">EXPERIMENTAL CATALOG · GENERATED {esc(generated)}</p>
<h1>One searchable food family, every source record preserved.</h1>
<p class="lede">This test database turns preparation-heavy USDA result lists into canonical food families. It retains the original {len(foods):,} records for audit and detailed selection, while exposing {len(groups):,} representative search records with all member names indexed as aliases.</p>
<section class="grid">
<div class="metric"><b>{len(foods):,}</b><span>original source foods</span></div>
<div class="metric"><b>{len(groups):,}</b><span>canonical search foods</span></div>
<div class="metric"><b>{reduction:,}</b><span>rows consolidated</span></div>
<div class="metric"><b>{reduction_percent:.1f}%</b><span>smaller result surface</span></div>
</section>
<div class="note"><strong>Interpretation:</strong> a group means “these are alternate catalog descriptions of a similar food concept,” not “their nutrition is interchangeable.” The canonical row supplies default nutrition; preparation families with wide nutrient ranges must be reviewed before production use.</div>

<h2>What changed</h2>
<div class="two">
<section class="panel"><h3>Group-size distribution</h3>{bucket_bars}</section>
<section class="panel"><h3>Grouping methods</h3><table><thead><tr><th>Method</th><th>Groups</th></tr></thead><tbody>{method_rows}</tbody></table></section>
</div>

<h2>Search impact</h2>
<p>Counts use the same token-prefix matching and ranking shape as the app. The grouped index searches canonical titles plus every retained member title.</p>
<div class="table-wrap"><table><thead><tr><th>Query</th><th>Original matches · top results</th><th>Grouped matches · top results</th><th>Reduction</th></tr></thead><tbody>{search_rows}</tbody></table></div>

<h2>Chicken breast case study</h2>
<p>The broad generic family is represented by one neutral record, while deli, tender, roll, branded, and restaurant forms remain separate when their core identity is materially different.</p>
<div class="table-wrap"><table><thead><tr><th>Canonical title</th><th>Members</th><th>Chosen record</th><th>kcal / 100 g</th><th>protein / 100 g</th><th>Method</th></tr></thead><tbody>{''.join(group_row(group, True) for group in chicken)}</tbody></table></div>

<h2>Largest consolidations</h2>
<input id="largest-filter" type="search" placeholder="Filter these groups by title, alias, or source record…" aria-label="Filter largest groups">
<div class="table-wrap"><table id="largest-table"><thead><tr><th>Canonical title</th><th>Members</th><th>Chosen record</th><th>kcal / 100 g</th><th>protein / 100 g</th><th>Method</th></tr></thead><tbody>{''.join(group_row(group, True) for group in largest)}</tbody></table></div>

<h2>Highest-review nutrient spreads</h2>
<p>These preparation families have the largest calorie range among their retained members. They are the first candidates for splitting, adding a preparation chooser, or changing the canonical record.</p>
<div class="table-wrap"><table><thead><tr><th>Canonical title</th><th>Members</th><th>Chosen record</th><th>kcal / 100 g</th><th>protein / 100 g</th><th>Method</th></tr></thead><tbody>{''.join(group_row(group, True) for group in widest)}</tbody></table></div>

<h2>Database design</h2>
<div class="two">
<section class="panel"><h3>Preservation</h3><p><code>source_foods</code> contains every original row. <code>food_group_members</code> maps those rows to a stable SHA-1-derived group ID. Nothing from the source catalog is discarded.</p></section>
<section class="panel"><h3>Search surface</h3><p><code>foods</code> contains one chosen record per group. <code>foods_fts</code> indexes the canonical title, brand, and every original member title as aliases, so preparation-specific queries continue to match.</p></section>
</div>
<section class="panel" style="margin-top:16px"><h3>Representative selection</h3><p>The canonical chooser penalizes fried, breaded, sauced, restaurant, skin-on, and raw variants; favors neutral roasted, grilled, baked, skinless, or meat-only records; then selects nutrition near the group's median and uses source rank and serving data as tie-breakers.</p></section>
<pre class="panel schema">source_foods ({len(foods):,} rows)
   └── food_group_members ({len(foods):,} rows)
          └── food_groups ({len(groups):,} rows)
                 └── foods + foods_fts ({len(groups):,} searchable canonical rows)

Original sources: USDA {source_counts.get('usda', 0):,}; Open Food Facts {source_counts.get('off', 0):,}
Canonical sources: USDA {canonical_source_counts.get('usda', 0):,}; Open Food Facts {canonical_source_counts.get('off', 0):,}
Input: {esc(source_path.resolve())}
       {esc(file_size_mib(source_path))}
Output: {esc(output_path.resolve())}
        {esc(file_size_mib(output_path))} (larger because it retains source, mapping, canonical, and alias data)</pre>

<h2>Recommendation</h2>
<p>Use the grouped database as a search experiment, but do not replace the bundled catalog yet. First review the high-spread groups, then decide whether tapping a canonical result should use its default record immediately or open a preparation picker. The latter preserves the cleaner search list without implying that raw, roasted, skin-on, and fried nutrition are equivalent.</p>
</main>
<script>
const filter = document.getElementById('largest-filter');
const rows = [...document.querySelectorAll('#largest-table tbody tr')];
filter.addEventListener('input', () => {{
  const query = filter.value.trim().toLocaleLowerCase();
  for (const row of rows) row.hidden = query && !row.dataset.search.toLocaleLowerCase().includes(query);
}});
</script></body></html>
"""
    return report


def validate_output(path: Path, source_count: int, group_count: int) -> None:
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    try:
        checks = {
            "source_foods": source_count,
            "food_group_members": source_count,
            "food_groups": group_count,
            "foods": group_count,
            "foods_fts": group_count,
        }
        for table, expected in checks.items():
            actual = database.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            if actual != expected:
                raise RuntimeError(f"{table} contains {actual:,} rows; expected {expected:,}")
        duplicate_memberships = database.execute(
            """
            SELECT count(*) FROM (
                SELECT source, source_id FROM food_group_members
                GROUP BY source, source_id HAVING count(*) != 1
            )
            """
        ).fetchone()[0]
        if duplicate_memberships:
            raise RuntimeError(f"Found {duplicate_memberships} invalid group memberships")
        if database.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("Final SQLite integrity check failed")
    finally:
        database.close()


def main() -> int:
    arguments = parse_args()
    foods = read_foods(arguments.input)
    groups = build_groups(foods)
    create_database(arguments.output, arguments.input, foods, groups)
    validate_output(arguments.output, len(foods), len(groups))
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        render_report(arguments.input, arguments.output, foods, groups),
        encoding="utf-8",
    )
    grouped_rows = len(foods) - len(groups)
    print(f"Source foods: {len(foods):,}")
    print(f"Canonical foods: {len(groups):,} ({grouped_rows:,} fewer search rows)")
    print(f"Wrote grouped catalog to {arguments.output.resolve()}")
    print(f"Wrote HTML report to {arguments.report.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
