# Architecture

## Overview

The SwiftUI app has two local data layers:

1. A read-only, bundled SQLite catalog containing normalized food records and an
   FTS5 search index. `CatalogStore` performs source-filtered search and barcode
   lookup without loading the catalog into memory.
2. A small writable JSON document in Application Support managed by `DiaryStore`.
   It holds diary entries, favorites, meals, remembered quantities, custom foods,
   and imported MyFitnessPal records. Writes are atomic.

This split keeps a large catalog immutable and fast while making the personal
data schema easy to evolve and back up.

Custom foods and saved meals are separate collections in the personal document.
Settings presents them together as the Custom catalog while retaining their
different logging behavior. Remembered quantities are keyed by stable food ID,
so the same portion is available from favorites and later catalog searches.

## Catalog schema

Every food is normalized to a base quantity and unit plus calories, carbs, fat,
and protein for that quantity. All usable source portions are stored as compact
JSON so one food can expose choices such as ounces, grams, large egg,
tablespoon, cup, or branded serving without duplicating nutrition rows.
Searchable metadata is intentionally limited to source ID, name, brand,
barcode, source, serving description, and rank.

The build script imports USDA JSON and Open Food Facts API/export records into a
single format, deduplicates them, and builds an external-content FTS5 index.

## MyFitnessPal import

The importer accepts CSV files through the system file picker. Header aliases are
mapped to date, food name, amount, calories, carbohydrates, fat, and protein.
Imported rows become diary entries and unique foods become the MyFitnessPal
source. The mapping is deliberately isolated because the exact export supplied
by the user may require a small adapter update.
