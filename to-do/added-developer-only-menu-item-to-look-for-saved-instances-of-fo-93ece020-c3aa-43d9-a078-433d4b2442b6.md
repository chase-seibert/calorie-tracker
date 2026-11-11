## User requirements

- As a developer, I want a developer-only audit screen that finds saved foods, food configurations, and meals with unusually high calories, so that I can review questionable saved data.
- As a developer, I want to delete a selected audited item, so that an erroneous saved item can be removed without changing unrelated saved data or diary history.
- Assumption to resolve during implementation: use a visible, editable threshold, initially 1,000 kcal per saved serving, and show the calorie basis for every result. “Very high” has no defined threshold in the task.

## Architecture and data model

Add an audit destination under the existing `#if DEBUG` Developer Diagnostics area in Settings. Build its results from the current `DiaryStore` library state: custom foods, favorite food snapshots, saved food configurations, and saved meal templates (including imported templates if they are retained for reuse). Show each item’s kind, name, calories per serving/configuration, and threshold status; use the app’s existing nutrient calculation and meal aggregation rules.

Route deletion through the existing `DiaryStore` operations for custom foods, saved food configurations, and meals. Favorite-only food results need a targeted unfavorite operation; do not delete catalog foods. Deleting a meal template removes its favorite reference but must preserve already logged entries and their ingredient snapshots, as documented in `docs/sqlite-storage.md`. Deleting one result must not remove similarly named items or other configurations.

No material database schema or migration change is required. Keep the threshold as a developer preference in `UserDefaults`; persisted library mutations continue through the existing SQLite-backed repository transactions. If a single saved record appears through more than one saved collection, define stable identity and deletion scope so the audit does not imply that removing a favorite also removes its underlying custom food.

## Basic test cases

- A saved food below the threshold is absent from the high-calorie results; one at or above it appears with its serving calories and item type.
- A saved food configuration uses the configured serving/component nutrition and is flagged only when its computed calories meet the threshold.
- A saved meal’s displayed calories equal the sum produced by the existing meal nutrient calculation; changing the threshold updates results without changing saved data.
- Empty libraries and no matches show a clear empty state; zero, negative, or non-finite nutrition values do not crash or create misleading high-calorie results.
- Deleting a selected custom food, favorite-only food, configuration, or meal removes only that saved target and its appropriate favorite reference. A confirmation prevents accidental deletion.
- Deleting a saved meal leaves historical diary entries and their snapshots intact; deleting a saved food does not rewrite logged snapshots or meal ingredients.
- Relaunching or reloading the diary reflects a completed deletion, and release builds contain no audit entry point.

## High-level implementation details

1. Inspect `DeveloperDiagnosticsView` in `CalorieTracker/Views/SettingsView.swift`, saved item models in `CalorieTracker/Models/Domain.swift`, and the existing library mutations in `CalorieTracker/Data/DiaryStore.swift` and `DiaryEngine.swift`. Confirm what is meant by a “saved food instance” and settle whether favorites and imported meal snapshots are in scope.
2. Add a `#if DEBUG` navigation item and audit view. Derive candidates from current store state, calculate calories through existing domain methods, sort deterministically by calories, and provide an editable threshold with a documented default. Keep results clearly labeled as an audit, not a diagnosis of invalid data.
3. Use existing delete APIs where available. Add only the narrow store/engine mutation needed to remove a favorite-only item or saved configuration by stable ID. Present a destructive confirmation naming the exact target and refresh results after the transaction succeeds; surface failures without dropping the item optimistically.
4. Add focused domain/store and debug UI coverage for threshold boundaries, meal aggregation, identity/deletion scope, persistence reload, historical snapshot preservation, and DEBUG-only visibility. Use existing test targets and fixtures.
5. Verify with the repository’s appropriate simulator build and tests, then attempt `make phone-deploy` per repository guidance. Record any simulator, signing, device, or launch limitation precisely; this task does not require a schema migration.
