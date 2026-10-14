## User requirements

- As a user, I want the Calories chart to show a dotted line for my actual rolling average across the last 30 calendar days, so that I can compare recent intake with individual days and my daily target.
- As a user, I want gap days excluded from the average and cheat-day calories included, so that the reference uses days with recorded calorie data while preserving unusually high days.
- As a user, I want logged alcohol calories included in the daily calorie values and average, so that the graph reflects calories recorded for drinks as well as food.
- As a user, I want a key that names each reference line and gives the dotted target and actual-average lines different colors, so that I can tell them apart at a glance.
- Assumptions: the rolling window remains the chart's existing 30 calendar days; average every non-gap day in that window, including a non-gap day with zero calories. Alcohol entries with unspecified type continue to contribute their existing 150-calorie estimate.

## Architecture and data model

No material persistence, schema, or migration change is required. `TrendsView` already builds 30 `TrendPoint` values from `DiaryStore.totalsByDay(numberOfDays:)`; those daily nutrient totals include the calories from any logged alcohol entry. Use the full daily calorie total for the calorie series and compute the rolling average from non-gap points, retaining cheat-day and non-gap zero-calorie values. Add an explicit chart key for the dotted average and optional dotted target rules. This changes chart presentation and which existing daily calories the chart displays, but does not change stored diary data or the separate alcohol chart/focus preference.

## Basic test cases

- With varied totals over the rolling 30 calendar days, the dotted actual-average reference equals the arithmetic mean over non-gap days only.
- Mark a date as a gap day: its calories do not affect the average. Mark a date as a cheat day: its calories remain included, even when unusually high.
- Log food and an alcoholic drink on one day: the daily calorie series and average include both. An unspecified drink contributes the existing 150-calorie estimate.
- A non-gap day with zero calories contributes zero to the mean; when all eligible days are zero, the average line is at zero. A window containing only gap days avoids division by zero and presents no misleading average value.
- With a daily goal configured, the key identifies the target and actual average using distinct colors and matching dotted samples; without a goal, it still identifies the average. The goal key and line are absent when no goal is set.
- Adding a new day or editing calories updates the window's average. Toggling the Alcohol focus does not remove logged alcohol calories from the calorie series or average.

## High-level implementation details

1. In `CalorieTracker/Views/TrendsView.swift`, use each day's full total calories so the plotted series and average include logged alcohol calories. Continue using the 30-day `TrendPoint` collection and existing `.gap`/`.cheat` status; calculate the mean after excluding only gap points, with a no-eligible-days guard.
2. Add a dotted `RuleMark` for the average and render the optional daily-target rule dotted in a different color. Add a visible, accessible chart key with matching line samples, labels, and colors; show the target entry only when a target exists. Choose colors that remain distinguishable in supported appearances and avoid confusing either reference with the daily calorie series.
3. Update `docs/product-requirements.md` and `docs/design.md` to document the 30-calendar-day window, gap-day exclusion, cheat-day and alcohol inclusion, and the keyed, color-distinct reference lines.
4. Add focused coverage for calculation boundaries and verify the graph/key for gap and cheat days, alcohol calories (including the unspecified 150-calorie estimate), goal-on/goal-off, no eligible days, and overlapping reference values. For implementation, run `make test` and attempt `make phone-deploy`; report simulator, signing, device, or launch blockers precisely.
