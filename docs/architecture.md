# Architecture

## Overview

The SwiftUI app has two local data layers:

1. A read-only, bundled SQLite catalog containing normalized food records and an
   FTS5 search index. `CatalogStore` performs source-filtered search and barcode
   lookup without loading the catalog into memory.
2. A small writable JSON document in Application Support managed by `DiaryStore`.
   It holds diary entries, day statuses, the streak tracking start date,
   favorites, meals, remembered quantities, custom foods, imported MyFitnessPal
   records, and stable-ID custom food names. Writes are atomic.

This split keeps a large catalog immutable and fast while making the personal
data schema easy to evolve and back up.

When Apple Health is connected, `HealthKitStore` mirrors each diary entry as
four nutrition quantity samples: dietary energy, carbohydrates, total fat, and
protein. Each sample uses the diary entry UUID as a sync identifier, so edits
replace the previous samples and deletions remove only samples created by this
app. Authorization is requested only from Settings; HealthKit synchronization
is skipped until write access is granted.

On launch, `DiaryStore` finalizes every elapsed day since tracking began. Empty
days become gap days. When a calorie goal exists, nonempty days below 75% or
above 130% of the goal become automatic cheat days. Manual cheat-day labels are
authoritative. Logging into an automatic gap removes the label; undoing a cheat
day removes its optional calorie-only adjustment and restores normal logging.

Cheat days without an estimated adjustment preserve their local food entries
but replace this app's HealthKit samples for that date with zero-valued nutrition
samples. Cheat days with an adjustment sync their logged entries plus the
adjustment. Stable per-day HealthKit sync identifiers let later undo operations
remove the zero override safely.

The current streak walks backward across consecutive non-special days that have
food entries. An empty current day is ignored until it ends. The streak report
derives averages, calorie and macro ranges, and the most frequently logged food
or meal from those dates.

Diary rows use a small `UIViewRepresentable` collection-view adapter for
reordering and deletion. `UICollectionView` interactive movement provides the
long-press lift and live row displacement on iOS 18, while its list layout owns
the native full-swipe delete action. The adapter reports the final destination
index to `DiaryStore`, which normalizes and atomically persists display order.
This avoids overlapping custom drag and swipe gestures inside SwiftUI `List`.
Because the collection is non-scrolling inside the diary's SwiftUI scroll view,
it disables UIKit's automatic safe-area content-inset adjustment. The diary's
few top-level sections use eager vertical layout, avoiding stale lazy-stack
positions while the collection reports a new intrinsic height. The persistent
logging controls reserve the bottom safe area but ignore keyboard-only safe-area
changes from the food-picker sheet so they remain anchored after dismissal.

Custom foods and saved meals are separate collections in the personal document.
Settings presents them together as the Custom catalog while retaining their
different logging behavior. Remembered quantities are keyed by stable food ID,
so the same portion is available from favorites and later catalog searches.
Custom names use the same stable IDs, allowing a rename to flow through existing
diary entries and future personal search results.

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

## Simulator fixture mode

Debug builds running in the iOS Simulator load the checked-in
`CalorieTracker/Resources/Fixtures/DeviceDiaryFixture.json` instead of the
normal Application Support diary. The fixture is a date-relative snapshot of
the device diary: its captured current day is rebased to the simulator's
current day at launch, preserving the previous day's history and leaving the
next day empty. It includes the captured goal, favorites, saved meals,
remembered quantities, renamed food names, and all available diary history.

`make sim-launch` resets the fixture before each launch. Use
`make sim-launch SIMULATOR_FIXTURE=none` for a normal simulator diary. In
Xcode, set `CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE=1` for the same result.
UI tests can opt into the same data with `CALORIE_TRACKER_FIXTURE=device` and
`CALORIE_TRACKER_FIXTURE_RESET=1`.

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
