#!/usr/bin/env python3
"""Report missing-food coverage across one or more local SQLite catalogs.

The report uses the same token-prefix FTS matching and the same broad ranking
shape as CatalogStore.searchAll. It is intentionally offline and depends only
on Python's standard library.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path


DEFAULT_MISSING_DOC = Path(__file__).resolve().parents[1] / "docs" / "missing-foods.md"
SOURCE_TITLES = {"usda": "USDA", "off": "Open Food Facts"}


@dataclass(frozen=True)
class FoodMatch:
    source: str
    name: str
    brand: str | None
    source_id: str
    barcode: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--catalog",
        action="append",
        required=True,
        metavar="LABEL=PATH",
        help="Catalog to inspect; repeat for each variant",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--missing-doc", type=Path, default=DEFAULT_MISSING_DOC)
    return parser.parse_args()


def read_queries(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    section = text.split("## Current snapshot", 1)[-1].split("### Related results", 1)[0]
    rows: list[str] = []
    in_table = False
    for line in section.splitlines():
        if line.startswith("| Food or search |"):
            in_table = True
            continue
        if in_table and line.startswith("| ---"):
            continue
        if in_table and line.startswith("|"):
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if cells and cells[0] and cells[0] != "Food or search":
                rows.append(cells[0])
            continue
        if in_table and line and not line.startswith("|"):
            break
    if not rows:
        raise ValueError(f"No missing-food rows found in {path}")
    return rows


def fts_terms(query: str) -> str:
    tokens = [char for char in query if char.isalnum() or char.isspace()]
    normalized = "".join(tokens)
    words = normalized.split()[:8]
    if not words:
        raise ValueError(f"Search query has no searchable terms: {query!r}")
    return " ".join(f"{word}*" for word in words)


def open_catalogs(values: list[str]) -> list[tuple[str, sqlite3.Connection, Path]]:
    catalogs: list[tuple[str, sqlite3.Connection, Path]] = []
    for value in values:
        label, separator, raw_path = value.partition("=")
        if not separator or not label or not raw_path:
            raise ValueError(f"Catalog must use LABEL=PATH: {value!r}")
        path = Path(raw_path).resolve()
        if not path.is_file():
            raise FileNotFoundError(path)
        catalogs.append((label, sqlite3.connect(f"file:{path}?mode=ro", uri=True), path))
    return catalogs


def catalog_counts(database: sqlite3.Connection) -> dict[str, int]:
    return {
        source: count
        for source, count in database.execute(
            "SELECT source, count(*) FROM foods GROUP BY source ORDER BY source"
        )
    }


def matches(database: sqlite3.Connection, query: str) -> tuple[int, list[FoodMatch]]:
    terms = fts_terms(query)
    count = database.execute(
        """
        SELECT count(*)
        FROM foods_fts
        WHERE foods_fts MATCH ?
        """,
        (terms,),
    ).fetchone()[0]
    rows = database.execute(
        """
        SELECT f.source, f.name, f.brand, f.source_id, f.barcode
        FROM foods_fts
        JOIN foods f ON f.rowid = foods_fts.rowid
        WHERE foods_fts MATCH ?
        ORDER BY
            CASE
                WHEN lower(f.name) = lower(?) THEN 0
                WHEN lower(f.name) LIKE lower(?) || ',%' THEN 1
                WHEN lower(f.name) LIKE lower(?) || '%' THEN 2
                ELSE 3
            END,
            bm25(foods_fts, 8.0, 3.0),
            length(f.name),
            f.rank DESC
        LIMIT 5
        """,
        (terms, query, query, query),
    ).fetchall()
    return count, [FoodMatch(*row) for row in rows]


def markdown_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render_report(
    missing_doc: Path,
    catalog_results: list[tuple[str, Path, dict[str, int], dict[str, tuple[int, list[FoodMatch]]]]],
) -> str:
    generated = __import__("datetime").date.today().isoformat()
    lines = [
        "# Missing-food offline catalog report",
        "",
        f"Generated {generated} from [{missing_doc.name}]({missing_doc}).",
        "This report is an offline debugging artifact under `data/work/`; it is not included in the app target.",
        "",
        "## Catalog variants",
        "",
        "| Catalog | USDA entries | Open Food Facts entries | Total entries | SQLite file |",
        "| --- | ---: | ---: | ---: | --- |",
    ]
    for label, path, counts, _ in catalog_results:
        usda = counts.get("usda", 0)
        off = counts.get("off", 0)
        lines.append(f"| {markdown_cell(label)} | {usda:,} | {off:,} | {usda + off:,} | `{path}` |")

    for query in catalog_results[0][3]:
        lines.extend(["", f"## {query}", ""])
        lines.append("| Catalog | Matches | Top five matches |")
        lines.append("| --- | ---: | --- |")
        for label, _, _, results in catalog_results:
            count, top = results[query]
            if top:
                formatted = "<br>".join(
                    f"{index}. {SOURCE_TITLES.get(row.source, row.source)} — "
                    f"{row.brand + ' — ' if row.brand else ''}{row.name}"
                    f"{f' ({row.barcode})' if row.barcode else ''}"
                    for index, row in enumerate(top, 1)
                )
            else:
                formatted = "—"
            lines.append(f"| {markdown_cell(label)} | {count:,} | {formatted} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    arguments = parse_args()
    queries = read_queries(arguments.missing_doc)
    catalogs = open_catalogs(arguments.catalog)
    results: list[tuple[str, Path, dict[str, int], dict[str, tuple[int, list[FoodMatch]]]]] = []
    try:
        for label, database, path in catalogs:
            query_results = {query: matches(database, query) for query in queries}
            results.append((label, path, catalog_counts(database), query_results))
    finally:
        for _, database, _ in catalogs:
            database.close()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(render_report(arguments.missing_doc, results), encoding="utf-8")
    print(f"Wrote coverage report to {arguments.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
