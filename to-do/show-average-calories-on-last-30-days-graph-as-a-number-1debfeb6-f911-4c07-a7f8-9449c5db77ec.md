## User requirements

- As a user, I want the 30-day calorie average shown as a number on the calorie graph, so that I can read the average without estimating it from the dotted line.
- Keep the number tied to the existing actual-average reference line and the existing fixed 30-day window. Assume the value should use the same calculation and eligibility rules already documented for that line; the task does not specify exact placement or decimal precision.

## Architecture and data model

No material architecture, persistence, schema, or migration change is required. `TrendsView` already derives daily points from `DiaryStore`, computes `actualCalorieAverage` with `CalorieTrendAverage`, and draws the average `RuleMark`. Present a numeric annotation from that same computed value so the visible number cannot drift from the plotted line. Preserve the existing behavior of omitting both line and number when the 30-day window contains only gap days.

## Basic test cases

- With a mix of ordinary, cheat, and gap days, show the average number at the plotted average; gaps are excluded and cheat days are included, matching `CalorieTrendAverage`.
- With a non-gap zero-calorie day, include that day in the displayed average, as the existing calculation does.
- With all days marked as gaps, show neither the average line nor its number.
- With an average of zero, display a valid zero value rather than hiding the annotation.
- Verify the annotation remains legible within the chart at common phone widths and does not obscure the calorie series or target reference line. Check accessibility exposes the value and identifies it as the 30-day average.

## High-level implementation details

1. In `CalorieTracker/Views/TrendsView.swift`, add a Swift Charts annotation to the existing actual-average `RuleMark` (or an equivalent chart label anchored to that mark). Format the value consistently as a whole calorie count with locale-aware grouping and a clear calorie/day label; keep the existing average line and key semantics.
2. Choose an annotation position and collision behavior that keeps the numeric label visible alongside the optional target line and the plotted series. Confirm appearance at narrow phone widths and with values near the chart bounds; adjust chart padding or placement only as needed.
3. Extend focused coverage in `CalorieTrackerTests/CalorieTrackerTests.swift` for the display formatting or extracted presentation helper if one is introduced. Existing `CalorieTrendAverage` tests already cover gap exclusion, cheat-day and zero-day inclusion, and the all-gap case; retain those rules.
4. Update `docs/design.md` and/or `docs/product-requirements.md` to state that the actual average is numerically labeled if that is now part of the intended chart behavior.
5. Verify with the repository's prescribed `make test`, then build/deploy using the required iPhone workflow (`make phone-deploy`) for an implementation. Resolve any annotation clipping or accessibility regressions before handoff.
