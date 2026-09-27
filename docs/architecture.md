# Architecture

## Overview

The SwiftUI app has two local data layers:

1. A read-only, bundled SQLite catalog containing normalized food records and an
   FTS5 search index. `CatalogStore` performs source-filtered search and barcode
   lookup without loading the catalog into memory.
2. A writable `Diary.sqlite` in the Yum Chase App Group container, managed by
   `DiaryRepository`. It stores entries and ingredient snapshots, day statuses,
   tracking settings, favorites, meals, quantities, personal foods, custom names,
   daily alcohol aggregates, quick-log receipts, and a durable HealthKit queue.
   `DiaryStore` is an asynchronous, bounded presentation cache.

This split keeps a large catalog immutable and fast while making the personal
data transactional across the app and extensions. See
[`sqlite-storage.md`](sqlite-storage.md) for the schema boundary, on-device state
inventory, one-off migration, backup rules, and performance measurements.

The main app and `VitaChaseWidgets` extension share App Group
`group.com.cseibert.CalorieTracker`. On first foreground launch, a legacy JSON
diary is backed up and verified before an atomic, no-replace SQLite publication.
Original JSON is never changed or deleted; subsequent launches use only SQLite.
Widgets cannot initialize or migrate a missing live database.
`QuickLogSnapshot` provides extension-safe Recent resolution, arbitrary-
timestamp Magic calculation, and calorie-goal progress. `QuickLogRepository`
uses the same SQLite transactions for App Intents and widget buttons. Normal
`DiaryStore` saves reload the widget timeline, while the app reloads the shared
document whenever it becomes active so background intent writes appear in the
diary.

Two App Intents are indexed by Siri and Shortcuts. `LogRecentItemIntent` uses an
`AppEntity` query backed only by ordered Recent items; an exact normalized name
returns the newest matching stable ID. Leading articles are ignored and a
conjunction of exact Recent names resolves to a composite selection; an unknown
name resolves to no entity. `CaloriesRemainingIntent` reports the signed
difference between the goal and today's food plus alcohol calories and converts
read failures into useful spoken guidance. The Quick Log widget reuses the log
intent, commits a short-lived receipt in SQLite alongside the log, and schedules
timeline entries at the next 5 AM, 11 AM, and 3 PM Magic band boundaries. A
separate Calories Left widget reloads on diary writes and at local midnight.
Dynamic Home Screen quick actions contain the current Magic stable IDs; UIKit
must launch or resume the main app to deliver those actions, so the main
`DiaryStore` handles them without presenting a confirmation dialog.
Both widgets assign a `vitachase://log-food` URL to their non-intent surface, and
the circular Add widget links to it directly. `RootView` validates that route
before presenting the diary's existing Log Food sheet; other URLs continue
through the document-import path.

The app exports `com.cseibert.calorietracker.food` and
`com.cseibert.calorietracker.meal`, backed by `.calfood` and `.calmeal`.
`RootView` handles incoming document URLs, reads security-scoped files, caps
imports at 256 KiB, validates the extension against the format identifier,
schema version, counts, lengths, numeric finiteness, and reasonable upper bounds,
then presents the corresponding review sheet. A one-off food becomes a normal
custom-source `Food` snapshot without joining `DiaryDocument.customFoods`. A
one-off meal becomes a `DiaryEntry` with component `MealItem` snapshots and no
saved-meal link, preserving quantity edits, break-apart, reports, and HealthKit
sync without joining `DiaryDocument.meals`. Each review offers an explicit opt-in
to save for reuse. See `docs/custom-import-files.md` for both public schemas.

When Apple Health is connected, `HealthKitStore` mirrors each diary entry as up
to five nutrition quantity samples: dietary energy, carbohydrates, total fat,
protein, and dietary Fiber when known. Each sample uses the diary entry UUID as
a sync identifier, so edits replace the previous samples and deletions remove
only samples created by this app. Authorization is requested only from Settings;
HealthKit synchronization is skipped until write access is granted.

Alcohol entries remain separate from food entries in storage but render as a
dedicated row in the diary's Logged section. They are excluded from food meal
selection and reordering while contributing their estimated calories to daily
totals, calorie goals, streak statistics, and automatic day classification.
`DiaryStore` converts each alcohol aggregate to a stable-ID, calorie-only
nutrition entry when synchronizing Apple Health. Trends reads the persisted
counts directly for a separate daily alcohol chart and subtracts the aggregate's
estimated calories from the food-calorie series. Alcohol calories remain in the
diary total and therefore continue to affect calorie goals and automatic day
classification.

On launch, the repository finalizes newly elapsed days since its last durable
finalization checkpoint. A goal edit deliberately recalculates history. Empty
days become gap days. When a calorie goal exists, nonempty days below 75% or
above 130% of the goal become automatic cheat days. Manual cheat-day labels are
authoritative. Logging into an automatic gap removes the label. A calorie-only
adjustment remains a separate diary entry. Its standard UI is limited to cheat
days; a DEBUG-only `UserDefaults` experiment can show the quick-calorie controls
on every day and preserve the adjustment when cheat status is removed.

Cheat days without a calorie adjustment preserve their local food entries
but replace this app's HealthKit samples for that date with zero-valued nutrition
samples. Cheat days with an adjustment sync their logged entries plus the
adjustment. Stable per-day HealthKit sync identifiers let status or adjustment
changes remove the zero override safely.

The current streak walks backward across consecutive days with at least one
food or meal entry. Calorie thresholds, manual cheat-day labels, and alcohol-only
days do not make a logged food day ineligible; a day with no food or meal ends
the streak. An empty current day is ignored until it ends. The streak report
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
changes from the food-picker sheet so they remain anchored after dismissal. The
fixed cheat-day and optional alcohol actions lead the row, while the primary Log
food action follows and expands to use the available width. The alcohol focus
preference removes its action entirely, allowing Log food to consume the freed
space without changing the compact cheat-day control.

Custom foods and saved meals are separate collections in the personal document.
Settings presents them together as the Personal Library while retaining their
different logging behavior. Remembered quantities are keyed by stable food ID,
so the same portion is available from favorites and later catalog searches.
Custom names use the same stable IDs, allowing a rename to flow through existing
diary entries and future personal search results.

The last explicitly selected weight unit is a lightweight `UserDefaults`
preference. It starts as ounces and changes only when the user selects ounces or
grams in a food quantity editor; natural portions do not replace it. A food's
remembered quantity remains authoritative. For foods without one, the app first
uses a high-confidence catalog portion: tablespoon for butter, a can or bottle
for beer and soft drinks, a cooked cup for rice, and a cut-sized piece for
chicken. It then considers discrete portions such as pieces, slices, bars, eggs,
packages, and containers, followed by the catalog's serving portion. Foods with
no suitable portion use the global one-ounce or 100-gram fallback. Technical
portions such as RACC, NFS, and yield measurements are never selected by these
defaults.

Catalog foods also carry two compiled presence flags: processed meat and
unprocessed red meat. The catalog builder derives them from USDA food categories,
FNDDS ingredient recipes, Open Food Facts category and ingredient tags, and
token-aware name rules. Source categories and ingredient lists remain build-time
inputs rather than shipped catalog payloads. `FoodResolver` fills missing flags
for new imports and custom foods using conservative catalog matching and name
rules, without changing nutrition or identity. Per-field provenance is stored in
existing SQLite row payloads. Historical corrections require explicit review and
a verified SQLite backup; normal launch and JSON conversion do not reclassify
history. See `docs/food-resolution.md` for matching and transaction boundaries.
Saved meals have optional explicit overrides and otherwise derive both flags from
their component foods.

Meat trends convert confirmed classified quantities into serving equivalents,
then group the fixed 30-day Trends window by the device's calendar week.
Meal ingredients are counted from their historical snapshots; an explicit
meal-level classification falls back to the logged meal quantity when no
matching ingredient flag is available. The UI overlays portion-based reference
guidance separately from the logged serving totals.

The user's visible focus areas are lightweight `UserDefaults` preferences,
separate from the diary document because they affect presentation and snack
suggestions rather than stored food or diary data. Alcohol, Fiber, processed-meat, and red-meat preferences
default on to retain the existing experience. Settings exposes the durable
controls, while the Trends toolbar menu changes them in context. Both surfaces
bind to the same keys. Diary also reads the alcohol key to conditionally include
its quick-entry action; Fiber does not add one. Trends conditionally builds drink
annotations, Fiber bars, chart copy, meat series, legends, and week-detail groups
from those preferences. Alcohol calories remain in daily nutrition totals when
its display focus is off, and the meat card is omitted when both meat focuses
are off.

`SnackSuggestions` filters a curated on-device library into one deduplicated list
using the enabled focus areas. Protein is always included; processed/red-meat
exclusions apply to every suggestion. Each row can carry multiple focus badges,
and stable snack IDs keep selection unique. This does not read the diary, call a
model service, or invent catalog nutrients.

`SnackRemindersStore` uses an injectable `SnackRemindersClient`; the production
adapter uses EventKit's iOS 17+ full Reminders access API. Authorization is requested
only from an explicit list-choice or Add action. `UserDefaults` stores the chosen
list's identifier and display metadata, not a copy of reminder contents. Each Add
validates the saved destination, fetches only that list's incomplete reminders,
skips normalized-title or stable-URL matches, and stages new reminders for a single
commit. Failed saves reset pending EventKit changes. A missing/read-only list never
falls back to another list. Reminder contents, list names, and focus choices aren't
sent to analytics. See [snack suggestions](snack-suggestions.md) for the export
contract and physical-device acceptance checks.

`FirstTimeOnboarding` owns a versioned `UserDefaults` completion key. At launch,
an empty diary with no completion value presents `FirstTimeOnboardingView` as a
non-dismissible full-screen cover. Its required first page selects focus areas;
later optional pages explain cheat/gap/alcohol tracking, walk through Magic mode,
offer a daily calorie goal, connect Apple Health, and finish with history-import
guidance. Optional pages use a compact top-bar back chevron and Skip action,
with a prominent Log Food-style Next button floating at the lower right; the
focus page has no back or skip action.
A diary containing existing user data writes the completion value automatically
so upgrades do not interrupt established users. An explicit false value remains
authoritative, allowing the DEBUG-only Developer Diagnostics reset to restore all
focus defaults, recreate the Home root, and replay onboarding without changing
the diary document or any logged data.

The food-weight report is derived on demand from the local `DiaryDocument` and
does not create persistent report state. It filters to the current day and the
previous 89 calendar days, excludes calorie-only adjustments, expands
meals from each diary entry's stored component snapshot, and aggregates gram
weights by stable food ID before sorting. The UI displays rounded whole ounces;
its share action writes the same rows to a temporary Markdown file and passes
that file URL directly to `UIActivityViewController`, avoiding an additional
SwiftUI transfer-provider layer before the native iOS share sheet.

Magic suggestions are derived on-device from `DiaryDocument`; no learned state
or personal history leaves the phone. `DiaryStore` filters the most recent 10
days by the entry's actual local logging time, groups unique items by diary day,
and ranks individual frequency alongside two- and three-item co-occurrence.
Combinations must repeat on at least two days and appear on at least 60% as many
days as their most frequent member. This prevents weak incidental groupings from
displacing a strong singleton. Logging a suggested set reuses normal quick-log
and saved-meal paths once per item, so the suggestion itself never becomes a
combined meal entry.

Analytics uses a process-wide actor with a durable, backup-excluded queue under
Application Support. It batches at most 500 same-audience events, creates and
persists deterministic gzip bytes, signs the compressed payload with
HMAC-SHA256, coalesces nearby captures with a brief upload debounce, and retries
transient failures with persisted exponential backoff and jitter for up to 90
days. Configuration is loaded from a debug app-container
override or bundled `AnalyticsConfig.plist`; a missing or invalid configuration
disables analytics without affecting app behavior. A git-ignored local plist is
copied into builds when present, while the repository contains only a placeholder
example.

Food search records a terminal `food_search.no_match` event for a completed
query with no results. A completed search that returned results records
`food_search.nothing_selected` only when the picker is cleared or dismissed
without a diary log. Opening a quantity editor does not count as selection; its
Add action does. Failed camera and manual barcode lookups record
`barcode_search.no_match`. Exact failed queries and normalized barcodes are
bounded. Successful search-originated food logs include the bounded query,
one-based result rank, and stable item identity. Public catalog identity uses
the source ID and a short catalog content fingerprint; custom or imported items
use their pseudonymous local UUID without sending their user-authored names.
Debug builds also retain payloads in the 100-event diagnostics history so
developers can inspect exact events; Release builds do not retain this
additional diagnostics copy. The copied diagnostics summary omits payloads.

Debug builds expose a Developer Diagnostics hierarchy in Settings. Its
Analytics Events screen shows the most recent local events and their queued,
prepared, uploading, retry-scheduled, uploaded, rejected, expired, or stopped
state. Selecting an event opens its canonical event payload, including event
properties. Request headers, signatures, and configuration secrets are never
shown.

The broader product event catalog is documented in
[`analytics-events.md`](analytics-events.md). Feature-usage events carry only
coarse categorical context and counts; food names, meal contents, diary
quantities and nutrition values, alcohol details, and Health samples are
excluded.

## Catalog schema

Every food is normalized to a base quantity and unit plus calories, carbs, fat,
protein, and optional Fiber for that quantity. Fiber remains nullable so an
upstream omission is not interpreted as zero on an individual food. Trends uses
a best-effort daily Fiber total: known entries and known saved-meal components
are summed while unknown contributions are omitted. Existing catalog-backed
diary snapshots are backfilled by stable source ID, while older custom foods
remain unknown until edited. All usable source portions are stored as compact
JSON so one food can expose choices such as ounces, grams, large egg,
tablespoon, cup, or branded serving without duplicating nutrition rows.
Searchable metadata is intentionally limited to source ID, name, brand,
barcode, source, serving description, and rank. Two non-searchable boolean
columns record processed-meat and unprocessed-red-meat presence.

The build script imports USDA JSON and Open Food Facts API/export records into a
single format, deduplicates them, and builds an external-content FTS5 index.

## Simulator fixture mode

Debug builds running in the iOS Simulator load the checked-in
`CalorieTracker/Resources/Fixtures/DeviceDiaryFixture.json` instead of the
normal persistent diary. Each reset uses a new UUID-named SQLite database under
the App Group's `CalorieTracker/Fixtures/` directory so
the widget and App Intents can read it. It is a date-relative snapshot of
the device diary: its captured current day is rebased to the simulator's current
day at launch. The loader also normalizes repeated breakfast, lunch, and dinner
sets across the two previous days, then gives today and tomorrow unrelated sample
entries. This keeps Magic populated in every time range without treating a
suggested set as already logged, while ensuring Yesterday, Today, and Tomorrow
always contain diary rows. It includes the captured goal, favorites,
saved meals, remembered quantities, renamed food names, and all available diary
history.

Every manual Debug simulator launch resets and rebases the fixture by default,
including launches directly from Xcode. `make sim-launch` does the same. Use
`make sim-launch SIMULATOR_FIXTURE=none` for a normal simulator diary. In
Xcode, set `CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE=1` for the same result.
UI tests can opt into the same data with `CALORIE_TRACKER_FIXTURE=device` and
`CALORIE_TRACKER_FIXTURE_RESET=1`.

`make sim-import-fixture INPUT=/private/path/YumChase-Database.sqlite` is the
explicit imported-snapshot path. It validates the standalone SQLite file,
copies it to a new UUID-named fixture, selects that fixture through the shared
App Group defaults, and launches the Debug app without changing the normal
diary or the checked-in fixture.

## UI testing

The UI-test target launches against an isolated temporary diary when the
`CALORIE_TRACKER_UI_TEST_FIXTURE` environment variable is set. The reorder test
performs a real long-press drag, verifies the row moved on screen, relaunches the
app without resetting the fixture, and verifies the order persisted. It never
reads or modifies the user's normal App Group diary.

The UI-test target is intentionally isolated in the shared
`CalorieTrackerUITests` scheme. Normal app builds and `make test` must not build
or run it. Run `make ui-test-reorder` when a change affects the logged-food list,
its collection-view adapter, row gestures, drag behavior, deletion behavior, or
display-order persistence. Unrelated app and catalog changes should use the
normal unit-test path only.
