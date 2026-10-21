## User requirements

- Allow a food shown in search results to be soft-deleted so it no longer appears in future food searches.
- Provide a Settings destination where deleted foods can be reviewed and re-enabled.
- Preserve existing diary entries and saved data when a food is hidden; re-enabling restores search visibility without changing its identity or history.
- Apply the behavior to catalog and personal foods returned by the food search flow. Meals are outside this request.

## Architecture and data model

- Add persisted hidden-food records to `DiaryDocument`, each holding the stable `Food.id` and a food snapshot. The ID (which includes source identity for catalog foods) keeps the user's choice stable across catalog refreshes; the snapshot keeps the Settings list readable when the source record is no longer available. Decode the new field as empty when absent for backward compatibility.
- Carry the field through `DiarySettings` serialization and SQLite snapshot/apply paths, since settings are persisted in the diary database. Keep catalog records immutable and avoid copying catalog foods into the personal-food collection just to hide them.
- Add `DiaryStore` operations to hide and restore a food, and filter matching foods in `DiaryEngine.searchItems` (or its shared search-result assembly) using the persisted identity set. Do not remove or rewrite logged entries, favorites, saved configurations, or food snapshots.
- Add a contextual row action in `SearchResultsList` for food results, including catalog and personal foods, with an accessible label and a clear destructive confirmation if needed to avoid accidental hiding. Refresh the visible search results after the action.
- Add a Settings list of hidden foods with a restore action, displayed from the saved snapshots. Keep the list sorted and explain that hiding affects search availability, not diary history.

## Basic test cases

- Hiding a catalog result removes it from subsequent matching search results; restoring it makes it searchable again.
- Hiding a personal food removes it from search results; restoring it returns it.
- A hidden food remains in existing diary entries, favorites, and saved food configurations, and its recorded nutrients and display remain unchanged.
- Hidden identities survive DiaryDocument encode/decode and SQLite save/reopen; older documents without the field decode with no hidden foods.
- A hidden catalog food remains identifiable in Settings after reopening the app, including when current catalog lookup cannot resolve it.
- Duplicate appearances of the same stable food identity are all suppressed, while distinct source identities with similar names remain independently controllable.
- Search-result hide/restore actions have accessible names, do not trigger quick add or food-detail selection, and refresh the current query correctly.

## High-level implementation details

1. Inspect existing `DiarySettings` schema and persistence tests, then extend the document/settings snapshot without dropping existing diary data or requiring a destructive database migration.
2. Add a backward-compatible persisted collection of hidden food records and transactional store/engine APIs to add or remove records by stable food ID.
3. Exclude hidden IDs from all food-result paths, including favorites, personal history, and bundled catalog matches; leave meal results and historical diary rendering untouched.
4. Add an explicit hide action to food search rows and a Settings management view that lists hidden foods and restores selected entries.
5. Add focused model, persistence, search, and UI interaction coverage for hide, restore, identity stability, and unchanged diary history.
