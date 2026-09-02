# Product requirements

## Snack suggestions

- Settings → Food & Meals includes Snack Suggestions, grouped by enabled focus
  area with high-protein picks always included.
- Almonds and other fiber sources appear under Fiber. Processed-meat and
  red-meat focuses exclude those meats from every section, not only their own.
- Ideas are generated from a curated on-device library with short reasons and
  serving tips; they don't require a network connection or change the diary.
- Users may select snacks and explicitly add them to an Apple Reminders list
  chosen once and remembered. List changes remain available. Permissions are
  requested on user action; selection alone never writes.
- Duplicate incomplete items are skipped. Missing/read-only lists and denied
  access fail visibly without writing to a different destination.
- See [snack suggestions](snack-suggestions.md) for scope and acceptance checks.

## Primary user stories

- As a calorie tracker, I want yesterday, today, and tomorrow immediately
  available so that navigating the dates I actually use is effortless.
- As someone who repeats foods, I want to log recent, frequent, and favorite
  foods with one tap so that routine tracking is as fast as possible.
- As someone logging outside the app, I want the app icon to expose the current
  Magic suggestions, Siri to log one or more exact recent foods or meals by name
  and report calories left, and Home or Lock Screen widgets to log
  time-appropriate Magic or recent items without opening the app.
- As someone whose breakfast and lunch repeat, I want Magic to suggest up to
  four foods or food sets from my last 10 days at that time of day, so I can
  log a routine with one tap without first turning it into a saved meal.
- As someone searching the catalog, I want the keyboard ready immediately and
  the current Magic suggestions visible before I type, followed by a one-tap add
  action on each search result using its visible quantity. Matching favorites and
  saved meals should appear first in alphabetical order, and saved meals should
  be searchable by name.
- As someone who weighs food, I want ounces initially plus grams and natural
  portions such as one large egg or one tablespoon, with remembered quantities
  per food and my last selected weight unit reused for new foods, so that
  entering a measured amount takes minimal editing.
- As a privacy- and speed-conscious user, I want diary storage and food search
  on-device so that routine use has no network latency or server dependency.
- As a data-source evaluator, I want one search to return USDA, Open Food Facts,
  and personal foods together, with source badges for comparing coverage and
  quality without an extra filtering step.
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
- As someone correcting a logged meal, I want to edit an individual ingredient's
  amount with its unit visible, without changing the reusable saved meal.
- As someone editing a saved meal, I want to search and browse foods by all foods,
  recent, frequent, or favorites, without seeing meals as selectable ingredients.
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
  catalog in Settings so I can add and edit custom foods and saved meals as well
  as confirm and manage what I have saved.
- As someone importing an AI-estimated meal, I want its component foods retained
  in an imported meal snapshot for Recent and repeat logging without having that
  snapshot appear in my hand-created Saved Meals catalog.
- As someone who estimates photographed food manually with an AI assistant, I
  want to open a small app-owned food or meal file, review its calories and
  macros, and log it without sharing my conversation or cluttering my personal
  catalogs.
- As a user looking for patterns, I want calorie and macro trends by day.
- As someone comparing intake with health targets, I want Trends to show a
  daily calorie target, a daily fiber recommendation, and weekly red- and
  processed-meat guidance alongside the charts.
- As someone tracking alcohol without itemizing every drink, I want a fast daily
  drink count with an optional single type, estimated calories, and drink-count
  trends.
- As someone limiting meat-related health risks, I want Trends to show how many
  days in each week contained processed meat and how many contained unprocessed
  red meat, regardless of quantity.
- As someone with specific nutrition priorities, I want to choose which focused
  food metrics appear in Trends so the app emphasizes only what I care about.
- As a new user, I want to choose my nutrition focus areas before I start
  tracking so the diary and Trends emphasize the metrics that matter to me.
- As someone analyzing what I eat, I want to share a last-90-days Markdown
  report of foods by total whole-ounce weight, with meals expanded into their
  historical component foods, so I can send it to ChatGPT and ask questions.
- As someone who sometimes takes a day off from tracking, I want an empty past
  day recorded as a gap day and removed automatically if I later log food.
- As someone whose log may be intentionally incomplete, I want past days below
  75% or above 130% of my optional calorie goal classified as cheat days, with
  a manual override and optional calorie estimate.
- As someone building a consistent habit, I want a visible streak count and a
  report covering calories, macros, ranges, and my most-logged item during the
  current streak, where each day with at least one logged food or meal counts.

## Interaction and presentation requirements

- The compact navigation title appears only after the macro summary card is
  fully above the visible diary. It shows consumed calories, includes the
  optional goal when configured, updates with diary changes, and restores the
  normal “Yum Chase” title when the card returns.
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
  Trends, which uses a fixed 30-day window without alternate range controls.
- The top diary bar keeps the lightning-bolt streak count and Settings so the
  compact calorie summary has room in portrait. The bottom safe-area bar gives
  compact orange cheat-day and alcohol actions first, followed by a larger Log
  food button that receives most of the width. When the Alcohol focus is
  disabled, its quick-entry action is omitted and Log food expands into the
  available space while Cheat day remains compact. An active cheat day adds a
  green check to the orange action icon and disables food and alcohol logging
  until the user confirms that they want to undo it from the icon, status banner,
  or logging action.
- Alcohol quick entry stores one aggregate count and one optional type per day.
  Plus and minus change the count; reopening edits that same aggregate, and zero
  removes it. An unspecified drink uses 150 calories; beer uses 150, wine 125,
  spirits 100, and cocktails 200 calories per drink. A saved aggregate appears
  as an orange wine-glass row in Logged and can be tapped to edit it. Alcohol
  calories contribute to diary totals. When the Alcohol focus is enabled, Trends
  shows each day's count in a separate alcohol chart, while the calorie chart
  shows food calories against the daily target.
- Foods carry independent processed-meat and unprocessed-red-meat presence flags.
  Processed meat includes cured, salted, smoked, fermented, dried, or otherwise
  preserved meat from red meat or poultry. Red meat means unprocessed mammalian
  meat. A mixed food may carry both flags. Trends groups diary days by the
  device calendar week and counts each category at most once per day. Tapping a
  week shows the qualifying foods grouped by day and category. Custom food,
  saved-meal, and import review editors expose both flags.
- Foods may also carry dietary Fiber grams. Catalog, custom-food, and import
  values scale with logged quantity and aggregate through meals. Individual
  foods may have unavailable Fiber; the 30-day daily-grams chart is best effort
  and sums every entry or meal component with known Fiber. Fiber does not become
  a Home quick-entry action or a fourth segment in the carbohydrate-inclusive
  macro bar.
- Settings and the Trends toolbar expose Alcohol, Fiber, Processed Meat, and Red
  Meat, in that order, as independent focus toggles. Disabling Alcohol hides drink
  markers, alcohol-specific chart labels, and the diary's alcohol quick-entry
  action but does not remove alcohol calories from the daily total. Disabling
  Fiber hides its chart without changing logged nutrition or Home. A disabled meat
  focus is omitted from the weekly chart, its legend, and the tapped-week detail.
  Disabling both meat focuses hides the meat-days card. All focuses remain enabled
  by default for compatibility with existing behavior, and logged data remains
  local regardless of display selection.
- A first launch with an empty diary presents a required focus-selection screen
  before the diary. Calories and macros are always included; Alcohol, Fiber,
  Processed Meat, and Red Meat are independently selectable and begin enabled.
  The next optional pages explain cheat days, gap days, and alcohol tracking,
  walk through Magic mode, offer a daily calorie goal, connect Apple Health, and
  finish with guidance for importing history from another app. Every page after
  focus can be skipped. Existing users with diary data skip this onboarding
  during upgrade, while a DEBUG-only developer action restores the default
  selections, returns to Home, and immediately presents onboarding again without
  deleting diary data, custom foods, or saved meals.
- Compact estimate pills above the Logged list offer calorie-only adjustments of
  500, 1,000, 1,500, and 2,000 calories on cheat days. A DEBUG-only, off-by-default
  “Always show quick calories” experiment exposes them on every day. Choosing
  another amount replaces the current adjustment, and Remove clears it.
- Marking a cheat day uses one Yes action. With the experiment disabled, undoing
  a cheat day also removes its adjustment; with it enabled, the adjustment is
  independent and remains on the now-normal day.
- Trends summarizes gap-day and cheat-day counts beneath its title for the fixed
  30-day window; those statuses do not add vertical markers to individual charts.
- Trends overlays a dashed calorie-target line when a daily goal is configured,
  a fiber recommendation based on 14 grams per 1,000 goal calories (28 grams
  when no goal is configured), and weekly meat guidance of no more than two
  red-meat days and little or no processed meat. The macro trend is a stacked
  area chart for carbohydrates, fat, and protein.
- Light and dark appearances use adaptive backgrounds, elevated cards, primary
  and secondary text, control fills, source badges, macro colors, and action
  colors across Diary, Log Food, quantity editing, Settings, and Trends.
- Yum Chase owns two versioned JSON formats: `.calfood` represents one
  aggregate food and `.calmeal` represents a named list of food snapshots.
  Opening either presents an editable review sheet before anything is saved.
  Log records one serving on the current day; saving to Custom foods or Saved
  meals is an explicit, off-by-default choice. Imported meals retain their
  component snapshots for Recent and remain breakable into their foods without
  entering the hand-created Saved Meals catalog. Invalid, mismatched-extension,
  oversized, and
  unsupported-version files show an error and do not mutate the diary.
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
- The Log Food sheet exposes Magic, Recent, Frequent, Favorites, Meals, and Scan
  modes; the diary's primary persistent action is the larger Log food button.
- Magic's explanation appears below its suggestions and lists the breakfast,
  lunch, and dinner time ranges.
- Home Screen icon quick actions mirror only the current Magic suggestions. iOS
  launches or resumes Yum Chase before the selected action is logged; the diary
  remains visible without an additional confirmation dialog.
- Siri and Shortcuts expose “Log Recent Food or Meal” and “Calories Left Today.”
  Exact spoken names resolve to the most recently logged matching Recent item;
  compound requests log every resolved name together. Items absent from Recent
  fail without logging, and a missing daily goal returns spoken guidance to
  configure one.
- The interactive Quick Log widget prefers Magic and falls back to Recent. Its
  timeline changes at 5 AM, 11 AM, and 3 PM local time. Small and Lock Screen
  widgets expose the leading action, the medium widget exposes up to three, and
  the large widget exposes up to eight. It shows a temporary visual receipt after
  logging. A separate Calories Left widget shows daily-goal progress. Widget
  buttons and App Intents update the shared diary without opening the app. The
  Calories Left widget, circular Add widget, and non-button Quick Log surface
  open the app directly to Log Food. Calories Left displays either “calories
  left” or “calories over” beneath the number; its thin progress ring adds a
  second pass with a dot between 100% and 200% of the goal.

## Explicit non-goals

No server database, accounts, manually assigned meal-of-day categories, weight,
water, exercise, steps, daily completion, server-generated recommendations, day
notes, or full micronutrient tracking in the initial app.
