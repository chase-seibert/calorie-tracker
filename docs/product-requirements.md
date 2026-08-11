# Product requirements

## Primary user stories

- As a calorie tracker, I want yesterday, today, and tomorrow immediately
  available so that navigating the dates I actually use is effortless.
- As someone who repeats foods, I want to log recent, frequent, and favorite
  foods with one tap so that routine tracking is faster than MyFitnessPal.
- As someone whose breakfast and lunch repeat, I want Magic to suggest up to
  four foods or food sets from my last 10 days at that time of day, so I can
  log a routine with one tap without first turning it into a saved meal.
- As someone searching the catalog, I want the keyboard ready immediately and
  the current Magic suggestions visible before I type, followed by a one-tap add
  action on each search result using its visible quantity. Matching favorites and
  saved meals should appear first in alphabetical order, and saved meals should
  be searchable by name.
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
- As someone logging a saved meal, I want to tap its list row to choose the
  number of servings, see its calorie and macro breakdown, and review its foods
  while renaming the meal without changing its constituent foods.
- As someone who uses personal names for foods, I want to rename a logged food
  and have that name persist in the diary and future searches.
- As someone tracking against a target, I want to set an optional daily calorie
  goal and see consumed calories, calories remaining, and a visual progress ring
  on the diary.
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
- As someone who sometimes takes a day off from tracking, I want an empty past
  day recorded as a gap day and removed automatically if I later log food.
- As someone whose log may be intentionally incomplete, I want past days below
  75% or above 130% of my optional calorie goal classified as cheat days, with
  a manual override and optional calorie estimate.
- As someone building a consistent habit, I want a visible streak count and a
  report covering calories, macros, ranges, and my most-logged item during the
  current streak.

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
- The diary toolbar orders the cheat-day action, lightning-bolt streak count,
  and Settings from left to right. An active cheat day adds a green check to
  the orange action icon and disables food logging until the user confirms that
  they want to undo it from the icon, status banner, or Log Food action.
- Marking a cheat day uses one Yes action. Once marked, compact estimate pills
  offer 500, 1,000, 1,500, and 2,000 calories above the Logged list. The chosen
  value appears as one calorie-only “Cheat day adjustment,” and choosing another
  value replaces it.
- Gap and cheat days appear as distinct vertical markers with a key in both
  trend charts.
- Light and dark appearances use adaptive backgrounds, elevated cards, primary
  and secondary text, control fills, source badges, macro colors, and action
  colors across Diary, Log Food, quantity editing, Settings, and Trends.
- The icon-only Magic pill uses breakfast from 5–11 AM, lunch from 11 AM–3 PM,
  and dinner for the remaining hours in the device's local time. Repeated sets
  are promoted only when their members reliably co-occur; otherwise the most
  frequent individual foods remain ahead of weak combinations.
- A Magic set has one add button. Tapping it creates a normal diary entry for
  each suggested item and never creates a new saved meal from the set.
- Foods logged today remain eligible for Magic. A single-food suggestion
  normally requires logs on at least two previous days. If the food is already
  logged today, at least one previous day must contain two matching logs in the
  active time band. Today's entries never count toward historical frequency.
- The diary's compact mode strip omits Scan to remain on one line. Scan remains
  available in the full Log Food sheet.
- Magic's explanation appears below its suggestions and lists the breakfast,
  lunch, and dinner time ranges.

## Explicit non-goals

No server database, accounts, manually assigned meal-of-day categories, weight,
water, exercise, steps, daily completion, server-generated recommendations, day
notes, or full micronutrient tracking in the initial app.
