# Design

## Principles

1. The default screen answers “what have I logged today?” immediately.
2. Repeated-food flows optimize for one tap; search results use a lightweight
   quantity sheet before logging when an amount has not yet been remembered.
3. Only calories, carbohydrates, fat, and protein are visually prominent.
4. Source identity is visible but quiet, making the dataset bake-off possible
   without cluttering routine use.

## Navigation

- **Diary** is the sole root screen: date strip, macro summary, entries, a
  prominent add button, and an upper-right Settings button.
- **Settings** contains source counts, data attribution, import, data
  management, and a link to Trends.
- **Trends**, nested under Settings, shows calorie and macro daily charts.

When the macro summary card scrolls fully out of view, its calorie total remains
visible as a compact navigation-title item and continues updating with the diary.
An optional daily calorie goal is configured in Settings. When present, both the
summary card and compact title show consumed calories followed by a smaller goal
denominator; without a goal, they retain the single calorie total.

The Custom source row in Settings shows separate food and meal counts and opens
a personal catalog with Custom Foods and Saved Meals sections.

The add-food sheet opens with an already-focused search field and keyboard.
Before typing, it shows combined For You suggestions plus wrapped filters for
Recent, Frequent, Favorites, Meals, and Scan without a redundant section title.
Typing immediately replaces the suggestions with combined MyFitnessPal, USDA,
and Open Food Facts results; Search is not a separate mode or source picker.

Every food row displays the quantity and calories that will be logged. Its
trailing + button logs that displayed remembered or default quantity and closes
the sheet; tapping the rest of the row opens quantity editing. Quantity entry
starts in ounces for a new food and offers every natural portion retained from
the source dataset.

The Select control beside the Logged heading enters meal selection mode. The
user explicitly checks one or more entries and names the combination. The
selected entries are replaced at their first position by one meal entry with the
same calorie and macro totals; unrelated foods remain in place.
Each meal entry exposes a visible actions menu to break the meal back into its
original food entries in place. This does not delete the reusable saved meal.
Outside selection mode, touching and holding any diary row starts reordering.
Rows animate into their new positions as the dragged item crosses them, and the
resulting order is stored locally. Long press has no destructive menu; deletion
is exposed only as the trailing swipe action. The handle remains as a visual cue.
Tapping a non-meal diary entry opens the quantity editor with its logged amount
and unit selected. Saving updates that entry in place, recalculates daily totals,
and remembers the choice for the next time that food is logged.
Focusing the amount field selects its complete value so typing replaces it.
Return on a hardware keyboard saves immediately; the iPhone decimal keypad
provides the same Save action in its keyboard toolbar.

## Visual language

The app uses a warm off-white background, a coral calorie accent, and blue,
violet, and green macro accents. Rounded cards provide hierarchy without turning
the diary into a dashboard of unrelated features.
