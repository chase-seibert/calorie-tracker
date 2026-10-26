## User requirements

- As a user, I want an AI estimate option when food search finds no match, so that I can continue logging an uncommon food without first building a custom entry.
- As a user, I want the estimate to use the searched food description and remain reviewable before logging, so that I can correct the result and choose whether to add it.
- Assumption: “AI generation” means reusing the existing OpenAI meal-analysis flow, prefilled with the search query. The existing flow returns an imported meal estimate, which may contain one or more foods; confirm whether this task expects a strictly single-food result.
- Keep the AI action out of component selection unless that flow is redesigned to return a draft component instead of logging to the diary.

## Architecture and data model

No material persistence, schema, or catalog change is required. Add a UI entry point from the no-results state in `SearchResultsList` through `FoodPickerView` to the existing `MealAnalysisView`. Seed the analysis description with the current query while allowing edits and optional photo input. Reuse `OpenAIMealAnalysisClient`, its existing credential and cost disclosures, error/retry behavior, and the `CustomMealImportView` review step. The estimate should not be logged until the existing review flow confirms it; no generated result should be inserted into the searchable catalog automatically.

## Basic test cases

- A completed search with zero matches shows an AI estimate action alongside the existing empty-state actions; while search is running, it does not show.
- Selecting the action opens the existing analysis screen with the trimmed search text prefilled. The user can edit it, add a photo, or cancel without logging anything.
- A successful analysis opens the existing estimate review; logging occurs only after the user confirms there. Verify the current imported-meal behavior for a single-food estimate and a multi-item estimate.
- Missing credentials, network/API failure, refusal, or an unestimable description show the existing actionable error and retry behavior without creating a diary entry.
- A query that returns results does not offer the no-results AI action. Component selection does not expose an action that would log to the diary.

## High-level implementation details

1. Extend the `MealAnalysisView` initializer with an optional initial description and initialize its editable description state from that value; preserve the current blank-description entry point from the mode strip.
2. Add an AI estimate callback to `SearchResultsList` and render an appropriately labeled action only after search completes with no results and outside component mode. Keep the existing custom-food and canonical-suggestion actions.
3. In `FoodPickerView`, open the existing analysis sheet with the current trimmed query and retain the existing search-attempt completion and dismissal behavior.
4. Update the search design documentation to describe the new empty-state action, its review-before-log behavior, and any single-food versus imported-meal distinction settled during implementation.
5. Add focused coverage for query prefill, empty-state visibility/eligibility, and preserving review-before-log behavior. Review the analysis error and cancellation paths so the query remains available for retry. Main risk: the existing analysis contract estimates a meal, not a canonical catalog food; preserve that contract unless product intent explicitly calls for a different result model.
