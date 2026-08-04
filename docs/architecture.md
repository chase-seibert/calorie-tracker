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

Diary rows use a small `UIViewRepresentable` collection-view adapter for
reordering and deletion. `UICollectionView` interactive movement provides the
long-press lift and live row displacement on iOS 18, while its list layout owns
the native full-swipe delete action. The adapter reports the final destination
index to `DiaryStore`, which normalizes and atomically persists display order.
This avoids overlapping custom drag and swipe gestures inside SwiftUI `List`.

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

## UI testing

The UI-test target launches against an isolated temporary diary when the
`CALORIE_TRACKER_UI_TEST_FIXTURE` environment variable is set. The reorder test
performs a real long-press drag, verifies the row moved on screen, relaunches the
app without resetting the fixture, and verifies the order persisted. It never
reads or modifies the user's normal Application Support diary.

The UI-test target is intentionally isolated in the shared
`CalorieTrackerUITests` scheme. Normal app builds and `make test` must not build
or run it. Run `make ui-test-reorder` when a change affects the logged-food list,
its collection-view adapter, row gestures, drag behavior, deletion behavior, or
display-order persistence. Unrelated app and catalog changes should use the
normal unit-test path only.
