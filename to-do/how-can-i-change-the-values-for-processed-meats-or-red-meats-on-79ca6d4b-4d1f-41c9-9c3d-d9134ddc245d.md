## User requirements

- As a user, I want to change the processed-meat and red-meat values from a logged food's detail screen, so that the diary and meat trends reflect what I know about that item.
- As a user, I want a simple Yes/No pill choice for each classification, so that I can correct the two values independently.
- As a user, I want to find the classification controls at the bottom of the logged-food detail, below “Add Another Ingredient,” so that they are easy to locate while reviewing the item.
- As a user, I want saving a correction to preserve the food's nutrition, amount, portion, date, and diary identity.

Scope: the controls are for whether the logged food contains processed meat and unprocessed red meat, not its separate meat-serving quantity. The requested choices are Yes and No; there is no Automatic choice. When a food has no known starting classification, decide whether its pills start unselected or default to No before implementation.

## Architecture and data model

No material schema or migration change is needed. `DiaryEntry` already stores optional `processedMeatOverride` and `redMeatOverride` values, and `FoodCustomizationView` loads and saves them through the atomic `updateFoodDraft` path. Add the controls to that shared customization screen for logged entries, after the existing ingredient section, and persist the selected booleans as entry-level overrides.

Keep edits scoped to the logged entry. Do not change the bundled catalog or other entries with the same food identity. The existing catalog-food editor has identity-wide effects and is a separate workflow. Preserve meal-level and ingredient-level classification behavior.

## Basic test cases

- Open a logged food from the diary list, scroll below “Add Another Ingredient,” and confirm the final section presents Processed Meat and Red Meat, each with Yes/No pill controls.
- Select Yes for Processed Meat and No for Red Meat, save, reopen the same entry, and confirm both choices persist independently.
- Change only one classification and confirm the other is unchanged; verify Yes/Yes and No/No are also representable.
- Cancel without saving and confirm the logged values remain unchanged.
- Save classification-only changes and confirm entry identity, date, logged time, order, quantity, portion, nutrition totals, and unrelated chart overrides are preserved.
- Confirm unknown starting classifications follow the agreed initial-selection behavior and can be explicitly set to either Yes or No.
- Confirm meal-level overrides and meal ingredient classifications continue to behave as before.

## High-level implementation details

1. In the logged-entry branch of `FoodCustomizationView`, add a final classification section after the “Add Another Ingredient” content. Use the app's existing pill visual language for two mutually exclusive Yes/No choices per field; omit Automatic.
2. Initialize the pills from the logged food's current effective classification where available. Settle the initial display for unknown values before implementation, without adding a third user-selectable choice.
3. Save the two independent values through the existing logged-food draft update. Preserve historical nutrition and entry metadata for tags-only saves, including configured foods with frozen snapshots.
4. Add focused model and UI coverage for placement, the two-choice controls, independent saves, cancel, persistence, and preservation of unrelated entry data. Keep corrections entry-specific; any future apply-to-matching-foods action should be a separate, clearly scoped flow.
