## User requirements

- As a user editing or reviewing a meal whose contents extend beyond the screen, I want to scroll vertically through the full meal form, so that every ingredient and control remains reachable.
- As a user moving through a long meal, I want the meal summary and quantity/action controls to stay available while the content scrolls, so that I can review totals and save without losing my place.
- Assumption: this behavior applies to all contexts that share the meal composition screen (logged meal, saved meal, logging, and imported meal review). Preserve the current swipe-to-delete interaction for ingredient rows.

## Architecture and data model

The screenshot is from the logged-meal editor. `MealDetailView` supplies its notes, ingredient rows, Add Food control, meat tracking, and import-only controls as content to `CustomizationScreen`. That shared shell already separates a `ScrollView` from the pinned summary and quantity/action footer. Meal ingredient rows also attach a `DragGesture` for swipe-to-delete, which should be investigated as a possible conflict with vertical scrolling; confirm the cause before choosing the gesture adjustment.

No persistence, data-flow, schema, migration, or compatibility changes are required. Keep the summary and footer outside the scrolling region and keep the complete meal form inside it. If a shared-shell adjustment is needed, confirm that food customization and other callers retain their existing behavior.

## Basic test cases

- Open a meal with enough ingredients to exceed the available height. A vertical drag over an ingredient card scrolls through the list to Add Food, meat tracking, and any later import controls; the summary and quantity/action footer remain visible.
- Open a short meal that fits in the available height. Its content is fully visible and the screen does not move unexpectedly.
- Swipe an ingredient row horizontally. Its delete affordance still opens, vertical scrolling remains available, and confirming or cancelling removal behaves as before.
- Scroll while starting on a row's Customize control or other interactive content. The intended button remains tappable, and dragging vertically continues to scroll.
- Repeat the long-content check for logged, saved, logging, and imported meal contexts, including a compact-height device or larger text size where content needs more scrolling.

## High-level implementation details

1. Reproduce the reported layout using the attached screenshot as the reference: a logged meal with multiple ingredient cards, a fixed summary above, and fixed quantity/Save controls below.
2. Trace gesture ownership between the `MealDetailView` ingredient-row swipe gesture and `CustomizationScreen`'s scroll view. Adjust swipe recognition so horizontal row gestures do not prevent vertical scroll gestures from reaching the scroll view; preserve row delete hit targets and animations.
3. Check the shared screen's layout constraints and safe-area behavior on shorter viewports. Keep the meal form as the scrollable middle region and the existing summary and footer pinned; change the shared shell only if the reproduction shows its sizing contributes to the failure.
4. Add or update UI coverage with a long meal fixture that scrolls to the final meal controls and exercises horizontal swipe-to-delete. Cover a short meal and the shared contexts affected by any shell change.
5. Run the relevant UI coverage and repository verification, then follow the repository's task-completion guidance to attempt `make phone-deploy`; report simulator/device evidence separately from source or build success. The main risk is regressing row swipe behavior or another customization screen if the shared shell is changed.
