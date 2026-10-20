---
name: chase-analytics-suggestions
description: Pull and review recent Calorie Tracker production search analytics and the user's Debug food suggestions, identify search or catalog opportunities, and process evidence-backed suggestions. Use when asked to refresh analytics, review Debug suggestions, or act on search gaps in this repository.
---

# Calorie Tracker analytics suggestions

Use this workflow for Calorie Tracker search analytics and follow-up work in this repository.

## Refresh and analyze

1. Read `docs/search-ranking-evaluation.md` and `docs/analytics-events.md` for the current event contract, privacy limits, and ranking workflow. Treat Debug audience events as the user's own test activity, but keep Debug and production reports separate and label each clearly.
2. The analytics service checkout is `/Users/cseibert/projects/analytics-server`. Check that it exists and that there are no local changes that the pull could disturb. From that checkout, run `make pull-incremental NAMESPACE=calorie-tracker` to sync and import new event shards into its local `downloads/analytics.sqlite3`. Follow that checkout's `AGENTS.md` if the host AWS CLI is unavailable; its Docker fallback mounts AWS credentials read-only. Never print credentials or identity details.
3. Analyze production and Debug separately over the requested rolling window (90 days by default). Save each query-level report under the analytics server's ignored `downloads/` directory using `scripts/analyze_search_analytics.py --db ... --days 90 --audience production|debug --output ...`; the script's default filters are namespace `calorie-tracker` and the three food-search outcome events. Do not merge the reports. Debug search activity is personal calibration data, not production demand. Review Debug search patterns as personal calibration, not evidence of broader user demand.
4. Review Debug `food.suggestion_submitted` events as explicit user-authored catalog feedback. Use a read-only SQLite connection and select only `occurred_at` plus `kind`, `suggested_name`, `suggested_changes`, and `search_query` from `payload_json`; filter `namespace='calorie-tracker'`, `audience='debug'`, `event_type='food.suggestion_submitted'`, and the same inclusive `windowStart`/`windowEnd` as the Debug report. Order by `occurred_at`. Do not inspect or export other Debug event payloads unless the user asks. The search analyzer does not include suggestion-submission events, so this focused query is required when reviewing suggestions.
5. Keep the raw database, query-level reports, and user-authored suggestion text local in the analytics server's ignored `downloads/` directory. Search terms and suggestion text can be personal. Do not copy raw queries, local-item hashes, suggestion text, session data, or the database into shared docs, fixtures, or external services. Share only reviewed aggregate counts, public catalog IDs, and the specific suggestion text needed to explain a requested change.

## Processed-through checkpoint

Store the private checkpoint at `/Users/cseibert/projects/analytics-server/downloads/calorie-tracker-analytics-checkpoint.json`. After each audience report has been successfully generated and reviewed, run the checkpoint helper with that report, for example:

```sh
python3 .agents/skills/chase-analytics-suggestions/scripts/update_checkpoint.py \
  --checkpoint /Users/cseibert/projects/analytics-server/downloads/calorie-tracker-analytics-checkpoint.json \
  --report /Users/cseibert/projects/analytics-server/downloads/search-analytics-debug.json \
  --suggestions-reviewed
```

Use `--suggestions-reviewed` only after the focused Debug suggestion query was reviewed; omit it for production or when suggestions were not reviewed. The helper records a separate UTC `processedThrough` watermark per audience (and a separate Debug `suggestionsProcessedThrough` watermark), based on the report's `windowEnd`. It refuses to move a watermark backward and writes atomically. Update it only after successful review, never after a failed or partial pull/report/query.

The watermark marks the upper time boundary of a successfully reviewed rolling window; it is not an exclusive event-time cursor. Continue pulling incremental shards and reviewing the overlapping rolling window on each run so late-arriving events with older `occurred_at` values are not skipped. Do not describe every event before the watermark as processed if the report or suggestion query failed.

If incremental pull cannot run, report the precise blocker and analyze an existing local export only if its provenance and freshness are clear. Do not advance the checkpoint for a failed refresh. Do not call the Lambda full export as an automatic fallback: it can time out on large histories, and a partial response is not a fresh export. Never describe an unchanged database as freshly downloaded.

## Review the suggestions

The report groups `food_search.no_match`, `food_search.nothing_selected`, and `food_search.result_selected` by query, and includes selected item IDs, ranks, and IDs shown above a selection where available. Debug suggestion submissions explicitly state the user's requested food or catalog change; review each suggestion against the current catalog and supporting sources. Use repeated search patterns as leads for investigation, not as proof of general user intent or relevance. A selection may reflect convenience or availability. A query with no match may be personal or ambiguous.

For promising patterns:

- Separate likely catalog coverage gaps from spelling/alias normalization, ranking order, and abandoned or ambiguous searches.
- Resolve public catalog IDs against the current catalog and source data. Local food and meal identities are hashed; do not attempt to reverse them or treat them as public catalog evidence.
- For ranking changes, make a small local relevance fixture from reviewed, non-personal examples, run `make search-eval`, and inspect each affected query against the baseline before changing ranking behavior. Preserve explicit prepared-food searches while evaluating broad queries.
- For catalog enrichment, follow the repository's `chase-food-enrichment` skill and persist supported overrides through its documented workflow. Verify nutrition and canonical identity from credible sources; analytics alone cannot establish food identity or nutrition.
- Prefer a concise proposed change list tied to aggregate evidence and public IDs. When the user asks to process the suggestions, implement only findings supported by the evidence, keep edits within the requested scope, and summarize unresolved/ambiguous items instead of guessing.

After changes, run the focused checks relevant to the work, such as `make search-eval` for ranking or the catalog review workflow for catalog enrichment. Do not deploy, publish, or share private analytics as part of analysis.
