# Product requirements

## Primary user stories

- As a calorie tracker, I want yesterday, today, and tomorrow immediately
  available so that navigating the dates I actually use is effortless.
- As someone who repeats foods, I want to log recent, frequent, and favorite
  foods with one tap so that routine tracking is faster than MyFitnessPal.
- As someone searching the catalog, I want the keyboard ready immediately and
  a one-tap add action on each result using its visible quantity.
- As someone who weighs food, I want ounces by default plus grams and natural
  portions such as one large egg or one tablespoon, with remembered quantities,
  so that entering a measured amount takes minimal editing.
- As a privacy- and speed-conscious user, I want diary storage and food search
  on-device so that routine use has no network latency or server dependency.
- As a data-source evaluator, I want one search to return USDA, Open Food Facts,
  and MyFitnessPal history together, with source badges for comparing coverage
  and quality without an extra filtering step.
- As a packaged-food user, I want barcode lookup so that occasional scans are
  quick.
- As someone who repeats combinations, I want to select one or more diary foods,
  replace them with a named meal entry, break that entry back into its foods,
  and later log the saved meal as one diary entry that I can break apart.
- As someone reviewing a day's diary, I want to drag logged foods into my
  preferred order and have that order persist.
- As someone correcting a logged food, I want to tap its diary row and edit its
  quantity or unit in place so totals and my next-use default update immediately.
- As someone who uses personal names for foods, I want to rename a logged food
  and have that name persist in the diary and future searches.
- As someone tracking against a target, I want to set an optional daily calorie
  goal and see consumed calories alongside that goal on the diary.
- As someone scrolling a long diary, I want the current calorie total to replace
  the navigation title after the macro summary leaves the screen, so the total
  remains visible without taking permanent vertical space.
- As someone correcting a diary, I want logged foods to use the standard
  trailing swipe-to-delete gesture, with no persistent delete control competing
  with the row content.
- As someone who uses iOS in dark mode, I want every app surface and interaction
  to retain readable contrast and the same visual hierarchy as light mode.
- As someone who creates personal foods and meals, I want a browsable Custom
  catalog in Settings so I can confirm and manage what I have saved.
- As a user leaving MyFitnessPal, I want to import its export so that my history
  and personal recents can become the third data source.
- As a user looking for patterns, I want calorie and macro trends by day.

## Interaction and presentation requirements

- The compact navigation title appears only after the macro summary card is
  fully above the visible diary. It shows consumed calories, includes the
  optional goal when configured, updates with diary changes, and restores the
  normal “Calorie Tracker” title when the card returns.
- Logged-food deletion uses the native trailing swipe action and supports a full
  swipe. The normal row shows no trash button or destructive long-press action.
- Logged foods reorder through a long-press drag and visibly move as they are
  crossed, without displaying a persistent reorder handle.
- Diary multi-select keeps Cancel, Delete, and Create meal in a bottom safe-area
  action bar.
- Diary multi-select can delete all selected entries after confirmation.
- The diary summary displays carbs, fat, and protein as one stacked horizontal
  bar, in that order, with exact gram values in its legend.
- Tapping calories, carbs, fat, or protein in the diary summary navigates to
  Trends.
- Light and dark appearances use adaptive backgrounds, elevated cards, primary
  and secondary text, control fills, source badges, macro colors, and action
  colors across Diary, Log Food, quantity editing, Settings, and Trends.

## Explicit non-goals

No server database, accounts, meal-of-day categories, weight, water, exercise,
steps, daily completion, recommendations, day notes, or full micronutrient
tracking in the initial app.
