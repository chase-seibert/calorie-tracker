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
summary card and compact title show consumed calories followed by a smaller
denominator for calories remaining. The fire icon has an outer ring that fills
clockwise to the daily goal; without a goal, it retains a neutral track and the
single calorie total is shown.
The summary card presents carbohydrates, fat, and protein as a single stacked
horizontal bar in that order. Segment widths represent each macro's share of
total macro grams, and a color-keyed legend retains the exact gram values.
Tapping the calorie total or macro chart navigates directly to Trends.

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
Saved meal rows use the same interaction: + logs one meal, while tapping the
row opens the quantity editor in meal servings. The meal editor keeps the name
editable through the same pencil action as foods, shows the
calorie/carbohydrate/fat/protein breakdown, and lists the constituent foods
without offering edits to them. Logged meal rows open this same meal editor so
changing servings updates the entry and its break-apart quantities.

The Select control beside the Logged heading enters meal selection mode. The
user explicitly checks one or more entries and names the combination. The
selected entries are replaced at their first position by one meal entry with the
same calorie and macro totals; unrelated foods remain in place.
In selection mode, Cancel, Delete, and Create meal remain in a bottom safe-area
action bar rather than the navigation bar, keeping the actions within easy thumb reach. A
destructive Delete action in the same bar removes all selected diary entries
after confirmation.
Each meal entry exposes a visible actions menu to break the meal back into its
original food entries in place. This does not delete the reusable saved meal.
Logging a saved meal later also creates one meal entry rather than separate food
rows, retaining its original item breakdown for the same break-apart action.
Outside selection mode, touching and holding any diary row starts reordering.
Rows animate into their new positions as the dragged item crosses them, and the
resulting order is stored locally. Long press has no destructive menu; deletion
is exposed only through the native trailing swipe action. Rows do not show a
persistent reorder handle.
Tapping a diary entry opens the quantity editor with its logged amount selected.
For foods, the editor also selects the logged unit; for meals, it edits servings.
Saving updates that entry in place, recalculates daily totals, and remembers the
choice for the next time that food is logged.
The quantity editor also exposes a pencil action for renaming the food. A custom
name is persisted by stable food ID and is used by existing diary rows, personal
catalogs, favorites, and future search results.
Focusing the amount field selects its complete value so typing replaces it.
Return on a hardware keyboard saves immediately; the iPhone decimal keypad
provides the same Save action in its keyboard toolbar.

## Visual language

The app uses a warm off-white background, a coral calorie accent, and blue,
violet, and green macro accents. Rounded cards provide hierarchy without turning
the diary into a dashboard of unrelated features.
These roles use adaptive semantic colors: dark mode switches to grouped dark
surfaces, elevated cards, and system-aware text while retaining the same accent
relationships and contrast hierarchy.
