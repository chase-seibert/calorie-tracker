# Food search ranking evaluation

Food search telemetry records a bounded query, the stable identity selected,
its one-based result position, and the identities ranked above it. The app
captures `food_search.result_selected` when the user taps or quick-adds a row;
opening its quantity editor does not count as a selection. See
[`analytics-events.md`](analytics-events.md) for event limits and local-ID
handling.

## Offline baseline

Run `make search-eval` to evaluate the current bundled catalog against
[`relevance-v2.json`](../data/search-eval/relevance-v2.json). The output is
JSON with the query rationale, each expected item's exact rank, top ten actual
results, mean reciprocal rank, hit rate at five, target rate, catalog
fingerprint, and ranking-rule version. Override the fixture with
`make search-eval FIXTURE=path/to/fixture.json`.

The fixture is versioned and tied to a 12-character catalog fingerprint. A
fingerprint mismatch is included in the report so a catalog refresh cannot be
mistaken for a ranking-only change. Update the expected fingerprint only after
reviewing fixture IDs and rerunning the same queries. `relevance-v1.json` is
retained as the original first scored baseline; v2 updates the rice target to
the user-confirmed intent of plain cooked white rice
(`Rice, white, cooked, no added fat`). Missing selections, unreported ranks,
and unresolved bread/chicken item IDs are not guessed.

The command evaluates `CatalogStore.searchAll`, so it covers the bundled
catalog's FTS5 ranking only. It does not read the phone diary, favorites, saved
meals, or analytics. `DiaryEngine.searchItems` can prepend favorites, matching
saved meals, and recently logged personal foods. Unit tests cover that local
merge with explicit synthetic log timestamps and verify it remains
deterministic. Diary frequency is not currently an independent ranking weight.

## Metrics

- **Mean reciprocal rank:** average of `1 / rank` for the highest-ranked
  expected item in each query. Queries with no expected item in the results
  contribute zero.
- **Hit rate at five:** fraction of queries with any expected item in the first
  five results.
- **Target rate:** fraction of queries with any expected item at or above its
  declared `desiredMaxRank`.
- **Relevance:** human-authored grades in the fixture (3 is the primary target,
  2 is a preferred alternative). The initial metrics use target rank and do not
  convert these grades into a weighted score.

## Production observations and privacy

The evaluation Sheet's `Production Calibration` tab stores user-reported
partial observations separately from repeatable catalog runs. The account
analytics event stream is behavioral evidence, not relevance truth: a chosen
item can reflect availability or convenience. Local meal IDs and custom food
names are not public catalog identities. Do not export them, diary contents,
or the diary database to a shared Sheet. History-based ranking experiments
should use a narrowly scoped local fixture with explicit counts and most recent
log times, then report only approved aggregate results.

Before changing weights, compare one candidate rule against this same fixture,
inspect each query's changed rank, and retain the baseline and rule version.
Broad queries such as `rice` should reward a direct simple food match; explicit
queries such as `fried rice` must continue to return prepared-food matches.

## Analytics Server SQLite exports

The Analytics Server export contains an `events` table with `namespace`,
`event_type`, `occurred_at`, `app_version`, `audience`, and `payload_json`.
`make search-analytics SEARCH_ANALYTICS_DB=path/to/analytics.sqlite3` reads the
database in read-only mode and filters to the `calorie-tracker` namespace,
`production` audience, and the three food-search outcome events. It defaults to
the most recent 90 days; set `SEARCH_ANALYTICS_DAYS` to change the window. The
output groups outcomes by query and selected item, reports selected ranks, and
includes the result IDs above each selection when available. Catalog IDs stay
stable; local food and meal IDs are replaced with short stable hashes. No names,
session IDs, or account identifiers are emitted. Keep the source database and
analysis output local; only reviewed aggregates and public catalog IDs belong
in the shared evaluation Sheet.

The Analytics Server's `export-sqlite` action exports all configured namespaces
and audiences. The reader applies the production and Calorie Tracker filters
locally, so the SQLite export should remain private. A JSON report can be saved
with `--output path/to/search-analytics.json`.
