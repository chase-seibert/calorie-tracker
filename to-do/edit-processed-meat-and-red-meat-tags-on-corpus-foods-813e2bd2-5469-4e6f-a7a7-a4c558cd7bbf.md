## User requirements

- As a user, I want to change the processed-meat and red-meat tags for a food in the built-in corpus, so that its classification reflects what I know about that food.
- As a user, I want to set the two tags independently, so that correcting one does not silently change the other.
- As a user, I want to edit a corpus food's tags from its logged-food detail and from the food detail opened by tapping a column in the Last 30 Days meat chart, so that I can correct a classification where I notice it.
- Scope assumption: “corpus foods” means USDA and Open Food Facts records in the bundled catalog. The bundled catalog is read-only at runtime, so user edits should be saved as local overrides keyed by catalog source and source ID; they should not edit the upstream corpus or nutrition data.
- Scope assumption: edits made from a logged entry or meat-chart detail correct that corpus identity, so the edited tags should update the selected logged food and matching historical snapshots as well as future lookups. Preserve the existing explicit, backed-up correction safeguards when changing history.

## Architecture and data model

- `CatalogStore` reads the bundled `FoodCatalog.sqlite3` read-only and provides stable `(source, sourceID)` identities and catalog classifications. Keep that asset immutable during ordinary app use.
- Add a persistent, per-food override layer to diary-owned state, storing independent processed and red-meat choices for each corpus identity. An unset choice should mean automatic/catalog classification so a user can restore the default. Apply overrides after catalog resolution and before display/logging, and mark edited fields as user-sourced using the existing meat-resolution provenance model.
- Expose the same focused tag editor from the logged-food detail (`QuantityEditor(entry:)`) and from the detail sheet opened by tapping a weekly meat-chart column (`MeatWeekFoodsView`). The chart detail currently receives food-name strings; retain enough food identity and snapshot data in its rows to open the editor for the correct corpus food without relying on names.
- Treat save from either historical surface as an explicit classification correction: persist the corpus override and update the selected and matching logged snapshots through the repository transaction, preserving nutrients and meal-level overrides. Reuse the verified-backup and stale-snapshot protections of the existing classification correction flow.
- Keep overrides in the existing diary persistence path and Codable state rather than adding writable columns to the bundled catalog or changing its build pipeline. Default missing override state when decoding older diaries; no SQL table change is indicated. Confirm whether the additive document field requires a `schemaVersion` increment under the repository's migration policy.
- Reuse the existing classification semantics and user choices from `FoodMeatFields` / `CustomFoodEditorView`, but expose a focused tag-editing path for corpus foods instead of allowing edits to catalog nutrition, identity, or portions. The current editor and `DiaryEngine.updateCustomFood` path are limited to personal foods.

## Basic test cases

- Search for a corpus food, change only Processed Meat, save, and verify the red-meat choice, nutrients, serving data, and catalog identity remain unchanged.
- Change only Red Meat and then change both flags; verify each stored choice is independent and is reflected on the food after the editor closes.
- Restore a field to Automatic and verify the bundled catalog classification is used again for that field while a still-explicit choice for the other field remains in effect.
- Relaunch or reopen the diary and resolve the same corpus identity; verify the local override persists and applies consistently from search and barcode lookup where the identity matches.
- Edit a corpus item with no definite automatic classification; verify Automatic remains unknown rather than being coerced to No, and explicit Yes/No values are honored.
- Resolve a different source ID with the same display name; verify it does not inherit the edited food's override.
- Open the editor from a logged corpus-food detail, change a tag, and verify the displayed entry updates while its nutrients and serving data stay unchanged.
- Tap a column in the Last 30 Days meat chart, open the grouped-food detail, edit a corpus food's tag, and verify the correction is saved and the food appears under the resulting category in the detail/chart; non-corpus and unrelated same-name foods remain unchanged.
- Verify historical correction creates/validates its recovery backup and rejects a stale snapshot without partially changing diary history; relaunch and verify the override and corrected snapshots persist.

## High-level implementation details

1. Trace `Food` identity and meat provenance in `Domain.swift` and `FoodResolution.swift`, plus how `DiaryStore` / `DiaryRepository` persist Codable diary state. Define the override key from `FoodSource` and `sourceID`, not display name, and preserve separate automatic/user values for the two flags.
2. Add the per-corpus override collection to persisted diary state with backward-compatible decoding. Route save/reset through `DiaryStore` and the existing serialized repository mutation path; avoid direct writes to the bundled SQLite catalog.
3. Update food resolution/display paths so catalog overrides take precedence over automatic catalog values without changing nutrients or affecting a different corpus identity. Check search, barcode, favorites, recents, and log snapshot construction for consistent application.
4. Add the focused Automatic/Yes/No editor to corpus foods and expose it from search plus logged-food detail. On save, route the edit through the shared repository correction operation so matching history and the persistent override stay consistent.
5. Change `meatDayFoods` / `MeatWeekFoodsView` data from display-only names to identifiable food snapshots (or an equivalent safe lookup) so tapping the Last 30 Days meat-chart column provides an edit action for each corpus food. Preserve day/category grouping and avoid name-only matching.
6. Add domain, persistence, and UI coverage for independent edits, Automatic reset, old diary decoding, identity isolation, unchanged nutrition, both entry points, backup behavior, and stale-correction rollback. Run `make test`; use `make sim-compile` if CoreSimulator is unavailable, as documented in the repository instructions.
7. Update `docs/design.md` and `docs/food-resolution.md` to describe the edit entry points, corpus override precedence, and explicit backed-up history correction. Do not reclassify snapshots during ordinary lookup or logging.
