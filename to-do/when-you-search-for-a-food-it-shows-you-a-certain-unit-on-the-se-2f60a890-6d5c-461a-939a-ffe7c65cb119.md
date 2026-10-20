## User requirements

- As a user, I want the food customization screen to open with the same unit or serving portion shown for that food in search results, so that the quantity does not unexpectedly change when I tap the result.
- As a user, I want that displayed default to reflect the unit and portion I last used for the food when available, so that logging a familiar food stays consistent.
- Assumption: apply this to opening a food from search results; an explicitly selected saved configuration should continue to open its own configuration and portion.

## Architecture and data model

The existing `DiaryStore.preference(for:)` resolves remembered quantities and fallback preferences, and `FoodResultRow` already uses that value to display the search result. `FoodDetailView` currently initializes its unit separately and only loads a remembered preference on appearance for non-Chase Food entries. Pass the resolved search-result preference with the selected food into the detail presentation, then initialize its quantity controls and default-preference tracking from that value.

No material data-model, persistence, schema, or migration change is required: remembered quantity and portion data already exist. Keep explicit historical entry/component state and saved-configuration state authoritative when those flows open the detail screen.

## Basic test cases

- A food with a remembered grams preference shows grams in search and opens customization with grams selected.
- Foods with remembered ounces or serving preferences open with the corresponding unit; serving preferences use the remembered portion when that portion remains available.
- A Chase Food item follows the same remembered preference as other search sources.
- A food without a remembered preference opens with the same fallback unit/portion used by its search row, including natural-portion and last-weight-unit fallbacks.
- If a remembered serving portion is no longer available, customization falls back to a valid portion without losing the displayed unit intent or crashing.
- Opening a saved variation retains that variation's own configuration and portion; editing a historical diary entry retains its logged quantity.

## High-level implementation details

1. Trace the search row's preference resolution and `FoodSelection` presentation path in `FoodPickerView`; carry the same `QuantityPreference` used by the row when opening a plain food result.
2. Extend the new-food `FoodDetailView` initialization to accept that preference and set amount, unit choice, portion ID, and the baseline preference used when reporting the selected default. Preserve existing precedence for diary entries, existing components, and explicitly supplied saved configurations.
3. Remove or replace the separate on-appearance preference load so it cannot override the value passed from the row, especially for Chase Food. Keep other callers on their existing defaults unless they have a corresponding displayed preference to pass.
4. Add focused regression coverage for remembered grams, ounces, and serving portions, fallback preferences, Chase Food, and saved-configuration/historical-entry boundaries. Prefer a UI-level assertion for the visible unit picker on opening from search, with unit-preference model tests where they isolate fallback behavior.
5. Verify with the repository's focused test workflow and review the search-to-detail behavior across food sources. Watch for stale presentation state when the selected food changes; keep the preference attached to the same food selection rather than reading unrelated state after presentation.
6. Reproduction finding: a Chase Food item with a remembered grams or ounces preference is a deterministic source-level repro. Its search row displays `diary.preference(for:)`, while `FoodDetailView` starts with a serving and skips its on-appearance preference load for Chase Food. Confirm this path in the running app before treating it as runtime-verified.

**Plan status: Approved by the user on 2026-10-20.**
