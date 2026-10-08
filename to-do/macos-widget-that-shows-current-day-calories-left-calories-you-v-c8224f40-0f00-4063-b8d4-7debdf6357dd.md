## User requirements

- As a user, I want a Mac widget that follows the mobile home screen's calorie and macro summary layout, colors, and visual hierarchy, so that the widget feels like a glanceable extension of the app I already use.
- As a user, I want to see today's calories left (or calories over), the carbs, fat, and protein I have eaten, and a list of foods I logged today, so that I can understand my progress and what contributed to it without opening the diary.
- Assumption: the home screen component to mirror is `MacroSummary` in `DiaryView.swift`: a prominent calorie figure and progress icon above a stacked macro bar and colored macro totals. Macro values are consumed grams; the diary has no macro-goal model.
- Mac delivery is still an implementation decision: use the existing iPhone widget on Mac if that meets the request, or provide a native Mac widget and determine how its local diary is populated. The iOS App Group does not sync a diary to a separate Mac.

## Architecture and data model

- Extend the existing `VitaChaseCaloriesLeftWidget` entry/provider/view in `VitaChaseWidgets/VitaChaseWidgets.swift`. Its current `QuickLogRepository` snapshot reads the shared diary, and `SharedDiaryStorage.reloadWidget()` already refreshes its timeline after app and widget writes.
- Populate widget entries with today's consumed calories, goal/remaining state, consumed carbs/fat/protein, and a bounded list of today's diary entries. Reuse the diary's calendar-aware date and nutrition semantics; keep food ordering consistent with the diary and omit non-food adjustment rows from the food list.
- Use the mobile `MacroSummary` as the visual source: rounded card surface, prominent calorie number with progress icon, stacked carbs/fat/protein bar, and matching blue/purple/green macro colors and labels. Adapt spacing and typography to widget families; put logged-food rows beneath the summary in a size that can show them legibly.
- Keep calorie progress behavior for unset goals and over-goal days. Include alcohol calories in calorie totals as the current calorie-left calculation does; align macro totals with the diary's existing daily totals.
- No diary schema, persistence, or migration change is expected. A separate native Mac host/extension needs a supported way to access or sync diary data; App Group sharing alone only covers processes on the same device.

## Basic test cases

- Compare the widget's calorie figure, progress treatment, stacked macro proportions, labels, and colors with the mobile home screen for the same diary snapshot; verify logged-food rows appear below the summary.
- With several foods logged today, the widget shows the same calorie and macro totals as the mobile diary, and the food rows show only today's entries in diary order.
- Logging, editing, or deleting a food refreshes the widget and updates its totals and list. Entries from yesterday do not appear today.
- With no foods logged, the widget shows zero consumed and an empty-food state; with no calorie goal, it still shows today's food and macro totals with a clear goal-not-set state.
- When consumed calories exceed the goal, the widget shows the app's over-goal treatment and does not present a negative amount as calories left.
- A long day list is bounded to the available widget space; names and amounts remain readable in supported small/medium/large layouts and both light and dark appearances.
- Verify the chosen Mac delivery path can add and render the widget and read the intended diary. If a native Mac target is required, verify its diary source on a separately installed Mac rather than assuming the iPhone App Group is shared across devices.

## High-level implementation details

1. Confirm whether an iPhone widget displayed on Mac meets the task or whether this requires a native macOS WidgetKit extension. For a native extension, settle whether it reads a Mac-local diary or needs cross-device sync before implementation; that choice affects targets, entitlements, packaging, and data architecture.
2. Extend the existing calorie widget snapshot/provider with today's totals and a limited, display-ready food list, using the repository's calendar-aware day filtering and current calorie-goal rules.
3. Recreate the `MacroSummary` visual hierarchy and palette in the widget, accounting for WidgetKit family constraints. Use a larger family for the full summary plus food list, and preserve a compact calorie/macro presentation when space is limited. Keep the existing widget kind and timeline reload path so installed widgets update on diary changes and at local midnight.
4. Add focused provider/model tests for date filtering, totals, goal boundaries, empty/error states, ordering, and list bounds; build the relevant app and widget targets, then inspect visual parity and food-list legibility on the Mac delivery path selected in step 1. A phone deploy alone does not verify Mac widget availability or cross-device data.
