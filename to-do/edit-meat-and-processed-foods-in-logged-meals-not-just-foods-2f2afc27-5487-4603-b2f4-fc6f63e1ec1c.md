## User requirements

- As a user, I want to edit the processed-meat and red-meat classification of each ingredient in a logged meal, so that the meal's meat tracking reflects what I actually ate.
- As a user, I want to edit those classifications on any logged diary row, including custom foods and foods created from AI meal analysis, even when they are not catalog foods or saved meals.
- As a user, I want those corrections to apply only to that logged meal and ingredient, so that they do not silently change the food, saved meal template, or other diary entries.
- Assumption: each classification has independent Automatic, Yes, and No choices; Automatic uses the ingredient's existing classification source.

## Architecture and data model

Add optional processed-meat and red-meat overrides to `MealItem`, where `nil` means Automatic. Use the existing optional `DiaryEntry` overrides for direct edits to standalone logged rows, including custom or AI-generated foods. In the logged-entry editor, meal ingredient edits apply to the entry's ingredient snapshot. A directly corrected saved-meal log must detach its snapshot so later template edits cannot replace the correction. Resolve each override before the existing food classification, while retaining current meal-level fallback behavior for entries without an ingredient classified in a category.

Persist the optional values in existing Codable meal-item payloads and keep the diary entry's indexed processed/red summary fields consistent in the same transaction. No SQLite table migration is expected if these remain payload fields; verify backward-compatible decoding and normalized projections. Do not change nutrient values, portions, food identity, or corpus-wide overrides as a side effect.

## Basic test cases

- In a logged mixed meal, set one ingredient to Processed meat = Yes and Red meat = No. The selected ingredient appears only in the processed-meat detail, and the meal's totals reflect the correction.
- In a standalone custom/AI-generated logged food, set each tag independently and verify it appears in the matching meat detail, survives reload, and does not change another log or the food's Automatic classification.
- Set each flag independently to Yes, No, then Automatic. Verify the other flag is unchanged and Automatic restores the ingredient's existing classification.
- Edit a meal created from a saved template. Verify the edited diary entry keeps its correction after reload, while the saved template and a separate log of it retain their prior classifications.
- Correct an ingredient in a one-off/imported meal and verify the same entry-scoped behavior.
- From the meat chart detail, open the matching logged meal ingredient, edit its tags, and verify the updated category appears after refresh without changing another matching food.
- Verify classifications for unaffected foods and entries, meal quantities, portions, and nutrition remain unchanged; old records without override fields still decode and classify as before.

## High-level implementation details

1. Trace meat classification and chart aggregation in `DiaryEngine`, including explicit meal-level overrides and fallback contributions, then define how per-ingredient overrides take precedence without losing legacy fallback behavior.
2. Add optional independent overrides to `MealItem` and update classification/resolution helpers. Keep the edit scoped to the selected logged entry; use the existing meal update path that snapshots a saved meal when its ingredients are changed.
3. Extend `MealItemEditorRow` in the logged-meal form in `QuantityEditor(entry:)` with clear Automatic/Yes/No controls and mark the item list edited when a choice changes. Add the same independent choices for every logged diary row, using the `DiaryEntry` overrides so custom and AI-generated foods do not need catalog identity. Where the meat chart detail identifies a specific logged entry and ingredient, route its edit action to the same entry-scoped editor. Leave corpus-food editing in `CorpusFoodMeatTagEditor` separate.
4. Ensure `DiaryStore`/`DiaryEngine` persist the edited snapshot transactionally and `DiaryRepository` refreshes entry and ingredient payloads plus indexed summary flags. Add focused unit and repository round-trip tests for classification, isolation, legacy decoding, and failed/stale updates.
5. Run focused simulator tests and the repository's storage checks, then attempt `make phone-deploy` per repository guidance. Confirm phone launch separately from build/install; if unavailable, report the specific verification limit. Main risk is precedence between per-item corrections and meal-level fallback tags, especially for meals whose ingredients all resolve to No or Unknown.
