## User requirements

- Every USDA, Open Food Facts (OFF), Yum Chase/Chase Food, custom-food, and meal result in Log food search must open customization when tapped.
- All these items must use the Yum Chase customization layout: a pinned name/nutrition summary, a scrolling customization area, and a pinned portion/quantity footer with the primary action.
- Search, Recent, Frequent, Favorites, Meals, saved variations, logged diary entries, Trends, and ingredient drill-down must use this same interface. Adding an ingredient uses the existing shared search.
- Available data changes the sections and choices inside the screen. It must not select a different overall interface. Chase Food and meals can add foods; USDA and Open Food Facts items cannot.
- Log creates a new entry; Save changes updates the existing entry; Add to parent and Use changes return a child draft; Save Saved Meal explicitly updates the reusable template. Cancel discards the current draft.

This is the follow-up plan for task #196, based on the user's review of the first implementation. It replaces the earlier pre-implementation audit. Planning changes only this Markdown file; existing application changes remain in the working tree.

## Architecture and data model

### Current implementation audit

Source inspection on October 14, 2026, plus the two existing task screenshots. The reported USDA tap failure has not been reproduced in a live UI during this planning pass; its exact hit-testing cause remains to be confirmed during implementation.

| Current code | Remaining gap | Proposed change |
| --- | --- | --- |
| `SearchResultsList` and `FoodResultRow` in `Views/FoodPickerView.swift` | Only `.chaseFood` results supply `openAction`, which creates a real Button. USDA/OFF result detail relies on an outer `onTapGesture`, while the row also contains a separate action button. This is a likely weak point in the reported USDA failure. | Use an explicit primary detail Button for every source, with the shortcut as a sibling Button. Remove the source condition and outer selection gestures. Verify the reported failure before and after the change. |
| `FoodPickerList` and `MealListActionRow` in the same file | Recent/Frequent/Favorites foods and meal rows also use selection gestures. Action titles are passed through some callers but currently hard-coded to `Add` in these row bodies. | Extract one `SearchItemRow` for food and meal results and suggestion lists, honoring contextual labels and consistent tap targets. |
| `FoodDetailView` in `Views/FoodDetailView.swift` | It shares routes and commit contexts but still selects two complete view bodies by source: `ChaseFoodCustomizeView` or `QuantityEditor`. | Keep context adaptation; send every food to one rendered customization screen. Source capabilities supply sections and units. |
| `ChaseFoodCustomizeView` in the same file | It contains the desired pinned summary, macro bar, option pills, scrolling content, and quantity/action footer, mixed with Chase-specific option loading and commits. | Extract this actual layout and its visual components as the common screen. Keep option calculation and historical reconstruction in adapters. |
| `QuantityEditor` in the same file | USDA/OFF/custom foods use a different ScrollView, summary, quantity picker and inline primary button. | Move useful quantity/default, rename, classification and imported-definition behavior into adapters and common sections. Retire its separate screen body. |
| `MealDetailView` in `Views/MealDetailView.swift` | Meals already share composition and commit logic across contexts, but render a Form with a toolbar Save/Log button. | Retain its draft/commit logic and move composition into the same scrolling body, pinned summary and footer as other foods. |
| `CustomMealImportView`, `SavedMealEditorView`, `LoggedItemDetailView`, and Trends callers | These already adapt import/template/logged contexts to detail views. | Preserve these boundaries and point them at the unified screen; retain specialized definition fields and explicit template/global-edit scope. |

The previous implementation shared search and persistence and added configuration provenance, but did not complete visual unification. The existing UI tests select Yum Chase results with USDA and OFF disabled; they do not establish cross-catalog clickability or visual parity.

### One common screen

Extract a `CustomizationScreen` and reusable components from the existing Yum Chase screen, rather than copying its appearance into three editors:

1. **Pinned header:** Back, a meal-circle icon immediately before a meal title, item name, optional brand, and the contextual actions menu. Do not repeat catalog source names or show a separate title Edit link; use Rename in the menu. Center Suggest a change. Show the same calories, Carbs/Fat/Protein values and macro bar in the same position for every item, aligning labels and values on a shared text baseline. Preserve unknown fiber as unknown. Support long names and Dynamic Type.
2. **Scrolling body:** render capability-driven sections in a consistent order: explanatory/history or save-scope notice when needed; available option groups; ingredients/additions; notes and advanced editing. USDA and OFF foods do not offer Add another food; Yum Chase foods and meals do. Show meat classification only on meals, with Yes/No pills and no Automatic choice. Use the same card spacing, typography, colors and ingredient row components throughout.
3. **Pinned footer:** one quantity control and portion/unit menu, followed by one large primary button. The footer remains available while scrolling and responds consistently to keyboard presentation. Meals use meal counts; foods use their real portions, grams and ounces. Do not expose a meal's synthetic `baseAmountGrams = 1` as a physical weight.
4. **Contextual action:** Log Food, Save changes, Add to parent, Use changes, or Save Saved Meal. Keep save-scope explanations near the relevant content. Remove the competing toolbar primary action from meal detail.

| Item | Sections within the common screen |
| --- | --- |
| USDA food | Name, known nutrition and actual portions; notes and contextual actions. Do not offer added-food components. |
| OFF food | Same sections, with optional brand and real serving weight when available. Do not offer added-food components. |
| Yum Chase food | Existing option groups and pills, saved variations, and added-food components. |
| Saved or logged meal | Read-only ingredient quantity cards with a Customize modal for unit/value, Add another food, swipe-left-to-reveal Delete with confirmation, notes, and meal-level classifications. |
| Imported/photo meal | The same meal sections, with ingredient-definition editing, original notes and Save for reuse intent retained. |

Show option pills only when actual options exist. USDA/OFF items must not acquire invented variants, inferred ingredient lists, or fabricated portion weights. Food additions from search use one Plus action that adds the selected food directly to the parent draft and closes search. Added-food quantities and units remain read-only until Customize opens the unit/value modal. Saved meal quantities use the focused quantity editor. Imported nutrient-definition editing can remain a focused child editor. On meals, ingredient amounts and units remain read-only until Customize opens the unit/value modal. Delete stays hidden until the row is swiped left, then asks before removal; omit ingredient reordering controls.

The overflow menu calls the action Rename and contains Favorite, Rename, a divider, and Recent Variations; remove Edit Food Tags Throughout History. When a saved variation is selected, show Delete this variation below Suggest a change. Confirm deletion and remove only the reusable variation; existing diary entries remain unchanged. Foods do not show a pencil or Edit link next to the title. Food screens omit meat-classification controls; meal-level processed-meat and red-meat choices use Yes/No pills.

### Search and navigation

- The primary result button covers the source badge, name, secondary information and remaining row space, with a minimum 44-point target. Its shortcut is an independent sibling; pressing the shortcut must not also open detail or log twice.
- Use one row implementation for search and list modes, including meals. Keep saved-variation selection and its explicit shortcut independent too.
- Expose identical Button semantics to VoiceOver, keyboard and pointer users. Stable identifiers must include food source plus source ID, or meal UUID, to distinguish equally named results.
- Preserve filtering, canonical ranking, history merge, debounce/cancellation and source preferences. Tap handling must not depend on the catalog source.
- Keep one navigation owner per presented level. Back/Cancel returns to the exact originating search or parent draft, preserving the query, list mode and scroll position where practical.

### Drafts, calculation and persistence

- Preserve `FoodDetailView.Context`, `MealDetailView.Context`, and the existing transactional `DiaryStore`/`DiaryEngine`/`DiaryRepository` commit operations. The shared visual screen receives a draft, capabilities, computed totals, and a contextual commit action.
- Separate source adapters from presentation. Adapters load real portions/options and create the initial value draft. The shared screen must not contain a catalog-source switch selecting complete alternative layouts.
- Reuse `FoodConfigurationCalculator` and meal-item scaling. Generalize configured-food drafts to accept a USDA/OFF/custom base plus additions, with no catalog option definitions when none exist. Store the base snapshot separately from configured totals and preserve added-component IDs, quantities, units and multiplicity.
- Generalize the existing optional `FoodConfigurationSnapshot` and saved-variation flow wherever they assume Chase Food, including capability dispatch, saved-variation lookup and analytics source labels. A configuration snapshot does not imply a Chase Food catalog identity.
- Plain historical USDA/OFF entries must open as ordinary editable snapshots. Absence of a customization snapshot on an unconfigured food is normal. When an incomplete configured historical item opens, rebuild it from current catalog values in the unsaved draft and show a brief banner only when values change; saving updates only that diary entry.
- Preserve UUID/date/logged time/order, meat overrides, nullable fiber, imported notes, remembered quantities and the HealthKit queue. Unchanged Save must preserve exact historical totals. Child edits and Cancel must not persist preferences, library items, suggestions or diary entries.
- Logged meal changes remain entry-scoped and detach modified composition from a linked template. Explicit Saved Meal updates retain their documented linked-history policy. Rename remains deliberate; the item menu omits the corpus-tag editor.
- Prefer the existing optional row-payload fields; no catalog rewrite or SQL migration is expected. If implementation needs a persisted field, verify old decoding/export/repository round trips before deciding whether a migration is necessary.

## Basic test cases

Acceptance requires both working interactions and matching rendered layouts; a shared routing wrapper alone is insufficient.

| Scenario | Expected result |
| --- | --- |
| Search for a pinned USDA, OFF, Yum Chase and saved-meal fixture | Each result is an explicit detail Button. Name, source badge and row-space taps open the intended item. |
| Open those four items and a custom food | Same pinned header/macros, title editor, scrolling body, footer quantity controls, primary-button placement and Back behavior; only capability sections differ. Meals show their icon and Log Meal action. |
| Press a result's shortcut | Performs only its contextual shortcut; never also opens detail or produces a duplicate log. |
| Open equally named results from different sources | Correct source identity, portions and nutrition are shown; selectors are unambiguous. |
| Use Search, Recent, Frequent, Favorites, Meals, Magic suggestions or a saved variation | Each Magic item inside a grouped suggestion opens its own customization screen; the group Add action remains independent. Return preserves the originating search/list context. |
| Add a food while composing a parent | A Plus action adds it directly to the parent and closes food search; the added ingredient is display-only until Customize opens the quantity/unit modal. |
| Add a fractional USDA/OFF/custom ingredient to a food or meal | Add affects the parent draft only; totals and component amounts survive parent Save/reload. |
| Reopen a plain historical USDA/OFF entry | Original quantity, portion and totals remain intact, without an unnecessary rebuild warning. |
| Edit a meal ingredient | Quantity is display-only until Customize opens its unit/value modal; swipe Delete asks for confirmation. |
| Edit the main title or meat classification | Edit opens one name modal for foods and meals. Meal-level meat uses Yes/No pills, with no Automatic choice or per-ingredient meat controls. |
| Reopen an incomplete configured historical food | Open with an unsaved rebuild from current catalog values; show a brief banner only if values changed; Save updates only this diary item. |
| Reopen a complete configured food or meal | Frozen values remain readable; no doubled additions or unintended catalog repricing. |
| Cancel child, Cancel parent, or save unchanged | No unintended diary/library/preference changes; historical values remain exact. |
| Change grams/ounces/real portions or meal count | Physical mass is preserved across compatible food-unit conversions; meal count scales ingredients consistently. |
| Log versus edit entry versus save template | Creates one new entry, updates one existing entry, or applies the explicit template policy respectively. |
| Import/photo review and ingredient-definition edit | Same screen chrome; validation, notes, classifications and Save for reuse remain available; viewing/editing never starts another AI request. |
| Failed save, deleted/concurrently changed entry or repeated press | Clear error, draft retained, no recreation/duplicate/partial commit. |
| VoiceOver, large text, keyboard, long item names and scrolling | All result buttons work, labels remain legible, the footer stays reachable, and Back returns one level. |

Use deterministic fixtures containing USDA, OFF, Yum Chase and meals together; do not make a cross-source test that disables two of the sources. Capture side-by-side simulator evidence at matching device size for all four main item types. Preserve diary reorder and cheat-day checks, and distinguish pre-existing failures from newly introduced failures.

### Required simulator screenshots of the new UI

Screenshot capture is an implementation acceptance deliverable. Capture the actual
implemented screens in the simulator after the shared UI is connected, using
repeatable demo fixtures rather than personal diary data. Existing task screenshots
show the earlier interfaces and must not be used as evidence of the new unified UI.

| Item type | Fixture characteristics and entry point | Required screenshot |
| --- | --- | --- |
| USDA food with a natural portion | A fruit or similar food with a real named portion; open from Log food search | `usda-portioned-log.png` |
| USDA food logged by weight | A food with grams/ounces selected; open from Log food search | `usda-weight-log.png` |
| OFF packaged food | A branded product with known label nutrition and serving weight; open from Log food search | `off-packaged-log.png` |
| Yum Chase configurable food | Sandwich or taco with selected option groups and an added ingredient; open from Log food search | `yum-chase-configured-log.png` |
| Custom food | A manually created food with a custom serving; open from shared search or Favorites | `custom-food-log.png` |
| Saved meal | At least three ingredients, preferably from different sources; open from search or Meals | `saved-meal-log.png` |
| Imported meal | A reviewed `.calmeal` fixture with component definitions, notes and Save for reuse | `imported-meal-review.png` |
| Photo-analysis meal | A stored/demo analysis-result fixture shown in review; capture does not require another AI request | `photo-meal-review.png` |
| One-off logged meal | A meal snapshot without a saved template, opened from the diary | `one-off-meal-edit.png` |

For each row, capture the initial screen with the pinned name/nutrition summary
and the quantity/action footer visible. Also capture a scrolled body state for
configurable foods and meals, showing their options or ingredient cards while
both pinned regions remain visible. Capture a food unit-menu state and an
ingredient child-editor state to document the shared controls.

Reopen a logged USDA food, OFF food, Yum Chase food, and saved meal and capture
an `-edit` screenshot for each. These must show the restored quantities/content
and the Save changes action in the same screen layout. Add a child-editor
screenshot showing Add to parent or Use changes as appropriate.

Use the same simulator model, orientation, appearance, text size and viewport
for the main comparison. Keep the keyboard dismissed and let loading and
presentation animations settle. Record source/item identity, selected quantity,
unit/portion, entry point, and simulator/runtime in an evidence index. Identify
any fixture that cannot be exercised and the exact blocker; do not silently
omit a source or substitute a mockup.

Save individual, unaltered PNG captures under
`docs/evidence/task-196/unified-ui/`, using the filenames above plus clear
`-scrolled`, `-edit`, or `-child` suffixes. Include a Markdown index linking every
capture and a side-by-side comparison of USDA, OFF, Yum Chase and a saved meal.
Inspect the screenshots for matching header/footer placement, readable names
and labels, correct contextual actions, unclipped quantity controls, and
consistent component cards. Correct visual discrepancies before final capture.

Attach representative screenshots to task #196 through
`attach_task_screenshot`, using the latest task revision and a fresh operation
ID for each write. Verify the attachments by reading them back. Link the complete
screenshot index in the implementation handoff so all food and meal types can be
reviewed together. Simulator evidence does not replace the required physical
phone deployment attempt or establish physical-device acceptance.

## High-level implementation details

1. **Reproduce and fix row interaction first.** Add failing USDA/OFF/meal result-button UI coverage using real source identities. Replace gesture-dependent food/meal selection with the common explicit-button row, then check primary/shortcut separation across search and list modes.
2. **Extract the Yum Chase visual shell.** Move its pinned header, summary/macro bar, quantity controls and footer into reusable components with consistent accessibility identifiers. Preserve the established Yum Chase appearance while separating calculation and commit code.
3. **Move simple catalog foods into that shell.** Adapt the existing simple-food state/defaults and quantity conversions. Support configured additions with existing snapshot fields. Remove the standalone `QuantityEditor` body after parity is demonstrated.
4. **Move meals and import/template contexts into the shell.** Replace `MealDetailView`'s Form/toolbar layout with the common summary/body/footer. Reuse one ingredient-card implementation for meal ingredients and added foods. Retain focused raw-definition editors and contextual scope/actions.
5. **Audit every caller and remove parallel bodies.** Connect search, list modes, variations, logged diary entries, Trends, components, Saved Meals and import/photo review. Verify there is one rendered customization layout, without source-specific skins or independent duplicate quantity controls.
6. **Verify and hand off.** Add the source/layout acceptance matrix to `make ui-test-food-detail`; run `make test` with host permission, `make storage-test`, and applicable reorder/cheat-day checks. Use `TEST_DIAGNOSTICS=never` if the known post-failure diagnostic collection stalls. Complete the required simulator screenshot matrix and evidence index above, attach representative captures to #196, update design/architecture documentation, and attempt `make phone-deploy` over the existing app following `docs/sqlite-storage.md`. Report installation, launch and physical acceptance separately. Keep task completion user-controlled.

This revision is plan-only. No application source, build, test or device deployment is part of this planning pass.
