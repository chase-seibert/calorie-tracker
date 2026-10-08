## User requirements

- As a user, I want the app to record the search query, selected item, and its rank, so that real searches reveal where ranking is failing. The existing `food_search.result_selected` event already records these fields and the IDs ranked above the selection; preserve and verify this data path rather than duplicating it.
- As a user, I want to tell Codex which account-specific searches to run, what results I expect near the top, and why, so that the evaluation reflects my foods, habits, and meaning of a good result.
- As a user, I want a current Google Sheet view of my search evaluations and a dated history of later runs, so that I can see whether ranking is improving across repeated evaluation cycles.
- As a user, I want simple queries such as “rice” to show a plain, minimally qualified food such as white rice near the top, so that branded and prepared variants do not crowd out the basic result.
- As a user, I want relevant foods I have used before to receive an appropriate ranking boost, so that repeat choices are easier to find. Assume prior diary use is a candidate local signal; whether it counts all diary logs or only search-originated selections remains an implementation decision.
- As a user, I want integration tests to reproduce the catalog and personal-food history behind a ranking, so that changes to ranking rules can be checked for regressions.
- Treat this as an evergreen evaluation-and-tuning loop, not a one-time ranking change. Keep account data local by default; only put fields approved for sharing in the Google Sheet.

## Architecture and data model

- No diary schema migration is required for the initial evaluation loop. Search selection events are already emitted by `FoodPickerView`; local food-use history is available through the diary repository’s search snapshot. Keep personal-use ranking signals on device.
- Add a compact, versioned relevance fixture for query cases, stable expected item identities, and graded relevance (including the plain-food intent for broad terms). Keep the integration-test fixture format deterministic and reviewable: seed the required catalog rows and an explicit diary history for each item, including log count and most-recent-log ordering. Pin runs to a catalog fingerprint and ranking-rule version so comparisons are reproducible.
- Add a deterministic offline evaluator around the current `DiaryEngine.searchItems` / `CatalogStore.searchAll` path. Report top-1/top-k hit rate and reciprocal rank, with per-query expected and actual ranks and top results.
- Create a Google Sheet with a current-run view and append-only run history. Each row should identify the run date, query, expected relevant items and rationale, actual top results/ranks, selected item/rank when available, per-query metrics, catalog fingerprint, ranking-rule version, and proposed experiment. Keep score definitions consistent across runs; record source revision and any fixture changes so apparent gains can be traced.
- Analyze `food_search.result_selected` events as behavioral evidence: compare selected item/rank and items above it against the curated set, while treating a selection as an implicit preference signal rather than definitive relevance truth. The existing result-above list is property-bounded, so confirm it is sufficient for the analysis horizon and retain an item-to-query join using stable public IDs.
- Personal foods may require a current phone diary snapshot. If needed, obtain a local export/copy through the repository’s documented storage-safe workflow and use only a narrowly scoped local fixture for analysis. Do not put the diary database, private food names, or unrelated diary content in the shared sheet; agree on which account-specific names or identifiers may appear there.
- Introduce no new server, account, or diary persistence model for the initial loop. If measured results later justify a separately persisted preference signal or broader result-impression capture, define its retention, consent, migration, and catalog-version behavior before implementation.

## Basic test cases

- For broad “rice”, the curated expected plain rice item is present and ranks above prepared, flavored, or branded variants; the evaluator reports its exact rank and the expected top-k score.
- For a specific query such as “fried rice”, the intended prepared food remains relevant and is not demoted merely for being a variant.
- Calibration includes broad, branded, and personal-food queries. Each query has the user’s expected top results and a short rationale before it is scored; ambiguous or missing personal items are recorded as such rather than silently treated as bad ranking.
- A known-food query where the selected item is below an irrelevant result appears with the correct one-based rank and stable IDs in the behavioral analysis; a top-ranked selection is scored accordingly.
- Integration fixtures with the same catalog and diary history produce the same ordering. Variants with different log counts or a more recent log exercise the intended prior-use behavior, while an unrelated popular history item does not outrank a better textual match.
- Favorites retain their intended behavior, and personal foods, saved meals, and catalog foods remain deduplicated in the result list and evaluation output.
- No-match and search-abandoned cases remain distinct from result selection; opening a quantity editor alone does not count as a completed selection.
- A catalog fingerprint mismatch is reported explicitly or selects the matching fixture version; it must not produce a misleading comparison against stale item identities.
- Every evaluation cycle appends a dated run to the Sheet history and refreshes its current-run view without changing prior results; query or fixture edits remain visible as versioned changes.

## High-level implementation details

1. Verify the existing analytics event contract and end-to-end collection for `food_search.result_selected`, including taps, quick-adds, normalized query, selected identity/rank, IDs above the selection, event limits, and available history. Treat missing telemetry as a coverage gap.
2. Calibrate with the user: ask them to run a focused series of searches in their account, capture the actual result list and selection rank for each, and ask which results should be near the top and why. Include simple foods, qualified/prepared foods, and personal items; refine the set based on their answers.
3. If local catalog and analytics evidence cannot resolve personal-item ranking, request a safe diary snapshot from the phone using the storage guidance. Inspect only the food identities and log counts/recency needed for the evaluation; keep the source database local.
4. Build a compact relevance dataset from the calibration answers and reviewed historical searches. Store expected item IDs, graded relevance, rationale, catalog fingerprint, and account-history fixture reference. Add deterministic integration tests that seed explicit catalog contents plus explicit personal-food history (including counts and latest logged timestamps) and assert ranked results and metrics.
5. Run the current algorithm as the baseline and create the Google Sheet with the first run’s per-query results and summary. Establish a stable sheet schema that can append future runs and compare metric definitions, catalog/rule versions, expected results, actual ranks, and notes over time. Confirm the allowed personal data fields before sharing account-specific names or IDs there.
6. Propose one heuristic change at a time—exact/prefix match, simplicity/qualification, source rank, favorites, or prior personal use—and evaluate it against the same curated set and integration fixtures. Use capped or decayed frequency so history cannot overwhelm query relevance; record gains and regressions by query class in the Sheet before choosing a change.
7. Repeat the cycle periodically: add user-reviewed queries, preserve past run rows, refresh the current-run view, compare against the prior run, and adjust ranking only when the evaluation supports it. Set the cadence with the user during the first cycle.
8. Document the chosen ranking weights, metric and fixture versions, test workflow, Sheet fields, privacy boundary, and unresolved decision about whether prior use counts all diary logs or only search selections.

Material risks are sparse or biased selection data, catalog IDs that change meaning between snapshots, event truncation for long result lists, and a frequency boost that hides better text matches. Keep the initial baseline reproducible, protect phone-derived personal data, and inspect per-query changes before adopting any weight.
