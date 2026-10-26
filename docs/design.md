# Design

## Product identity

Use **Yum Chase** (with a space) in user-facing copy. The Home Screen icon is
the approved **Peach Mochi** artwork from the second icon exploration. Keep its
opaque, full-bleed 1024×1024 source square; iOS applies the icon mask. Internal
project names and persistent identifiers remain unchanged for compatibility.

## Principles

1. The default screen answers “what have I logged today?” immediately.
2. Repeated-food flows optimize for one tap; search results use a lightweight
   quantity sheet before logging when an amount has not yet been remembered.
3. Calories, carbohydrates, fat, and protein remain visually prominent; optional
   health-focus metrics live in Trends.
4. Source identity is visible but quiet, making the dataset bake-off possible
   without cluttering routine use.

## Navigation

- **Diary** is the sole root screen: date strip, macro summary, entries, a
  prominent add button, and an upper-right Settings button.
- **Settings** is a compact setup and management hub organized into Goals &
  Logging, Focus Areas, Food & Meals, Connections, and Data & Privacy. Its
  rows show current values or status so the user's setup is understandable at a
  glance.
- **Trends**, opened by tapping the diary summary, shows the last 30 days in a
  daily-calorie chart with optional daily-target and actual-average references,
  a separate daily alcohol
  drink chart, an optional daily Fiber chart with its recommendation line, and a
  stacked daily macro area chart. The alcohol chart uses a fixed 0–3 minimum
  scale and a dashed two-drink daily reference; the meat chart shows servings
  per week with guidance lines for red and processed meat. Compact, semantically tinted cheat-day and gap-day
  count pills sit beneath the “Last 30 Days” title instead of repeating status
  markers across the charts. Its toolbar contains focused health-metric controls
  and the food-weight report.

When the macro summary card scrolls fully out of view, its calorie total remains
visible as a compact navigation-title item and continues updating with the diary.
An optional daily calorie goal is configured in Settings. When present, the
summary card emphasizes remaining calories on the left as “N calories left” (or
“N calories over” once the goal is exceeded), while the fire icon retains the
consumed/goal value beneath it. The compact title continues to show consumed
calories over the daily goal. The fire icon has an outer ring that fills
clockwise to the daily goal; without a goal, it retains a neutral track and the
single calorie total is shown.
The summary card presents carbohydrates, fat, and protein as a single stacked
horizontal bar in that order. Segment widths represent each macro's share of
total macro grams, and a color-keyed legend retains the exact gram values.
Tapping the calorie total or macro chart navigates directly to Trends.

The Logged section exposes compact +500, +1,000, +1,500, and +2,000 estimated
calorie pills on cheat days. The DEBUG-only Developer Diagnostics → Experimental
Features screen contains an off-by-default “Always show quick calories” toggle
that exposes the pills on every day. One calorie-only adjustment may exist per
day; selecting a different amount replaces it, and Remove clears it.

The bottom action bar orders compact orange cheat-day and alcohol actions before
the primary Log food button, which receives most of the width. When the Alcohol
focus is disabled, its quick-entry action disappears and Log food expands into
the freed space while Cheat day remains compact. This leaves the top bar clear
for the scrolled calorie summary, streak count, and Settings. The
wine-glass action opens a compact alcohol entry sheet for the selected day. The
sheet keeps one aggregate count and one optional type per day; plus and minus
buttons change only the drink count. An unspecified drink uses 150 calories.
Beer uses 150, wine 125, spirits 100, and cocktails 200 calories per drink. The
selected estimate contributes to the diary calorie total without adding
carbohydrates, fat, protein, or Fiber. Reopening the sheet edits the same daily
aggregate, and saving zero removes it. The alcohol action displays the saved
count. The aggregate also appears as an orange wine-glass row in Logged; tapping
the row reopens its editor. Trends shows the drink count in a separate daily
alcohol chart; logged alcohol calories also appear in the daily-calorie chart.
That chart's dotted actual average covers its last 30 calendar days, excludes
gap days, and includes cheat days and non-gap zero-calorie days. A visible key
names the average and, when configured, the daily target, using distinct colors
for their dotted lines. If every day is a gap, no average line appears.

The Food & Meals section in Settings contains the Personal Library, AI Food &
Meal Import, and Food Data Sources rows. The Personal Library row shows separate
food and hand-created meal counts and opens a catalog with Custom Foods and Saved
Meals sections. Imported meal snapshots are retained for Recent and quick
logging, but are not included in this hand-created catalog. Each section has an
Add action; tapping or swiping a row opens an editor, while swipe-to-delete
remains available for both kinds of personal item.

The Focus Areas section in Settings and the matching Trends toolbar menu
contain independent Alcohol, Fiber, Processed Meat, and Red Meat switches in
that order. Both surfaces share the same local preferences. Disabling Alcohol hides
the diary's quick-entry action and alcohol chart while retaining alcohol calories
in the diary total. Trends omits disabled
meat series from the weekly chart and tapped-week detail; when neither meat focus
is selected, the meat-days card is omitted entirely so the screen remains
centered on the user's chosen metrics. Disabling Fiber removes its daily-grams
card without changing food data or the diary action bar. Fiber remains separate
from the stacked macro summary because it is already included in carbohydrates.
Days containing any food without Fiber data are omitted from the Fiber series
and identified by explanatory chart copy rather than represented as zero.

Food and import editors offer Automatic/Yes/No meat classification choices,
explain automatic suggestions, and warn about conflicting explicit values.
Settings → Food & Meals → Review Classifications offers backed-up, explicit
correction of matching historical food snapshots. Users can approve individual
suggestions or confirm Approve All, which shows the suggestion count and applies
the entire reviewed batch atomically after one verified backup. A stale suggestion
rejects the batch without partial changes. It currently covers processed and red
meat, preserving explicit meal overrides. Unknown entries remain excluded from
the confirmed serving totals until they are explicitly classified.

USDA and Open Food Facts classifications can also be corrected from food detail,
logged-food detail, and the weekly meat-chart detail. These edits are stored as
diary-owned overrides keyed by catalog source and source ID, with separate
Automatic/Yes/No choices for processed and red meat. Applying a correction
updates matching history after a verified SQLite backup while leaving nutrition,
servings, and the bundled read-only catalog unchanged. Returning both tags to
Automatic restores catalog resolution.

Settings also links to AI Food & Meal Import instructions and one copyable,
tool-neutral prompt. It always requests a named `.calmeal` with one or more
food components, including one component for a simple food. The prompt asks the
assistant to estimate plausible cooking butter, oils, dressings, and sauces when
calorically material, identify uncertainty, avoid double counting, and create a
fresh meal-name slug plus unique suffix for each filename.

Opening a `.calmeal` presents the native meal review sheet. It exposes editable
name, serving description, serving weight, calories, carbohydrates, fat, protein,
and notes for every component and shows a calculated meal total. The primary Log
action adds one serving to today. Saving to Saved meals is off by default. An
imported meal is stored as an imported meal snapshot with its component foods,
so it can appear in Recent, be logged again, inspected, rescaled, or broken
apart without being added to the hand-created Saved Meals catalog. Former
`.calfood` files are unsupported. Files contain only structured estimates; no
conversation URL or assistant account is shared.

The detail view for a one-off logged meal can save its current ingredient
snapshot to Saved meals or save and favorite it. These actions remain available
after logging; the promoted imported meal is reusable from the meal picker and
does not link back to or rewrite the diary entry's recorded history.

The Trends toolbar links to a food-weight report that previews the last 90
calendar days as foods sorted by exact total weight, displayed as whole ounces.
Logged saved meals are expanded from the component snapshots on their diary
entries. A Share toolbar action opens the native iOS share sheet with the report
as a named Markdown file so it can be sent directly to document-aware apps such
as ChatGPT.

The add-food sheet opens with an already-focused search field and keyboard, with
the current Magic suggestions filling the pane until the user starts typing.
The full Log Food sheet includes Magic, Recent, Frequent, Favorites, Meals, and
Scan modes. The Meals mode puts hand-created meals in a top section and imported
meal snapshots in a separate section below. Typing immediately replaces the
selected mode with combined
personal, USDA, and Open Food Facts results; Search is not a separate mode or
source picker. Matching favorite foods and saved meals lead the results in one
alphabetized group, and saved meals can be found by their names.
When no search result matches, the empty state offers a Create Manually action
that opens the custom food editor with the search text prefilled as the food
name. Saving from that flow logs one serving and closes the food picker. Create
Automatically is the primary action and opens the existing meal analysis
flow with the trimmed search text prefilled. Create Manually opens the custom
food editor as a secondary action. Both actions stay above the keyboard. The
description can be edited and a photo can be added; the generated result remains
an imported meal with one or more foods and goes through the existing review
screen before anything is logged. Suggest a canonical food appears only in
development builds. Automatic estimation and canonical suggestions are hidden
while choosing a component for another meal.

Magic opens with a short explanation and up to four suggestions learned from
the previous 10 days in the current local-time band. Before the first food is
logged today, it also includes bands that have passed: breakfast from 5–11 AM,
lunch from 11 AM–3 PM, and dinner otherwise. A suggestion can be one food or a
visually grouped set. Repeated, cohesive sets receive a modest ranking boost so
a strong routine such as cappuccino plus protein shake can lead, while a more
frequent singleton such as turkey sandwich stays ahead of an inconsistent lunch
pair. Multi-food sets use a thin coral outline and extra space below to distinguish
the set from adjacent single-food suggestions. One trailing + adds all items in a
set as separate diary entries. The
explanation sits below the suggestions and states all three time ranges.
Items inside Magic suggestions use the same source and saved-meal badges as the
other food lists.
Foods logged today remain eligible for Magic, but today never contributes to
recommendation frequency. If an item was logged today, it remains eligible only
when it was logged at least twice in the same time band on one of the previous
10 days. See `docs/magic-recommendations.md` for the complete selection and
ranking rules. The list stays stable after an add so the green confirmation
checkmark remains visible; reopening Magic recalculates from prior days again.

Every food row displays the quantity and calories that will be logged. Its
trailing + button logs that displayed remembered or default quantity and closes
the sheet; tapping the rest of the row opens quantity editing. Quantity entry
starts at one ounce before any weight-unit choice has been made. Selecting ounces
or grams in any food quantity editor makes that the fallback for foods without a
remembered quantity; the fallback amount is one ounce or 100 grams. Selecting a
natural portion does not replace the last weight-unit choice. Every natural
portion retained from the source dataset remains available.
Saved meal rows use the same interaction: + logs one meal, while tapping the
row opens the quantity editor in meal servings. The meal editor keeps the name
editable through the same pencil action as foods, shows the
calorie/carbohydrate/fat/protein breakdown, and lists the constituent foods
with clearly labeled, editable amounts and units. Logged meal rows open this
same meal editor so changing servings updates the entry and its break-apart
quantities; changing an ingredient creates an intentional per-entry snapshot
without changing the reusable saved meal. Adding an ingredient from the saved-meal
editor opens a food-only picker with search, All foods, Recent, Frequent, and
Favorites modes; meals are never offered as ingredients.

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
Every full-screen or sheet-hosted list and form hides its system scroll
background and exposes the shared adaptive app background, including empty
states and developer-only screens.

## Returning to food customization

Tap a logged food to reopen the same detail screen used after search. Chase
Foods restore the pinned summary, option groups, ingredients and quantity footer;
the action becomes Save changes. USDA, OFF and custom foods use that exact header,
macro summary, scrolling content and footer too, with only their available sections.
Brand/source information stays in the header and actual food portions remain in
the footer menu. Meals use the same layout with meal counts and shared ingredient
cards; their primary action sits in the footer. Recent, Frequent, Favorites and saved variation rows use
these destinations too. A variation's plus button remains an explicit shortcut.

Meals use one composition screen for logging, editing a diary entry, Saved Meal
editing, and imported/photo estimates. Add Food opens the shared search; tapping
an ingredient opens shared food detail. Child changes remain in the parent draft
until the parent commits. Cancel at either level discards that level's changes.
Imported components retain their editable nutrient definitions and notes.

Saving a logged item affects that entry; editing a Saved Meal explicitly states
that linked history will also be refreshed. Older configured entries with
incomplete customization provenance show their preserved ingredients/nutrition
and require confirmation before rebuilding with today's catalog values.
