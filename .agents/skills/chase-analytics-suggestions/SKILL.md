---
name: chase-analytics-suggestions
description: Pull and review recent production Calorie Tracker search analytics, identify search or catalog opportunities, and process evidence-backed suggestions. Use when asked to refresh analytics, review search suggestions, or act on search gaps in this repository.
---

# Calorie Tracker analytics suggestions

Use this workflow for Calorie Tracker search analytics and follow-up work in this repository.

## Refresh and analyze

1. Read `docs/search-ranking-evaluation.md` and `docs/analytics-events.md` for the current event contract, privacy limits, and ranking workflow.
2. The analytics service checkout is `/Users/cseibert/projects/analytics-server`. Check that it exists and that there are no local changes that the pull could disturb. From that checkout, run `make pull-incremental NAMESPACE=calorie-tracker` to sync and import new event shards into its local `downloads/analytics.sqlite3`. Follow that checkout's `AGENTS.md` if the host AWS CLI is unavailable; its Docker fallback mounts AWS credentials read-only. Never print credentials or identity details.
3. From this repository, analyze that database with `make search-analytics SEARCH_ANALYTICS_DB=/Users/cseibert/projects/analytics-server/downloads/analytics.sqlite3 SEARCH_ANALYTICS_DAYS=90 SEARCH_ANALYTICS_AUDIENCE=production`. Adjust the window only when the request calls for it. The analytics target defaults to production; keep it there unless the user explicitly asks for another audience, and label any non-production findings clearly.
4. Keep the raw database and query-level report local. Search text may contain personal terms. Do not copy raw queries, local-item hashes, session data, or the database into shared docs, fixtures, or external services. Share only reviewed aggregate counts and public catalog IDs when needed.

If incremental pull cannot run, report the precise blocker and analyze an existing local export only if its provenance and freshness are clear. Do not call the Lambda full export as an automatic fallback: it can time out on large histories, and a partial response is not a fresh export. Never describe an unchanged database as freshly downloaded.

## Review the suggestions

The report groups `food_search.no_match`, `food_search.nothing_selected`, and `food_search.result_selected` by query, and includes selected item IDs, ranks, and IDs shown above a selection where available. Use repeated patterns as leads for investigation, not as proof of user intent or relevance. A selection may reflect convenience or availability. A query with no match may be personal or ambiguous.

For promising patterns:

- Separate likely catalog coverage gaps from spelling/alias normalization, ranking order, and abandoned or ambiguous searches.
- Resolve public catalog IDs against the current catalog and source data. Local food and meal identities are hashed; do not attempt to reverse them or treat them as public catalog evidence.
- For ranking changes, make a small local relevance fixture from reviewed, non-personal examples, run `make search-eval`, and inspect each affected query against the baseline before changing ranking behavior. Preserve explicit prepared-food searches while evaluating broad queries.
- For catalog enrichment, follow the repository's `chase-food-enrichment` skill and persist supported overrides through its documented workflow. Verify nutrition and canonical identity from credible sources; analytics alone cannot establish food identity or nutrition.
- Prefer a concise proposed change list tied to aggregate evidence and public IDs. When the user asks to process the suggestions, implement only findings supported by the evidence, keep edits within the requested scope, and summarize unresolved/ambiguous items instead of guessing.

After changes, run the focused checks relevant to the work, such as `make search-eval` for ranking or the catalog review workflow for catalog enrichment. Do not deploy, publish, or share private analytics as part of analysis.
