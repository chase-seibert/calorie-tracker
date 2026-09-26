# Snack suggestions and Apple Reminders

Open **Settings → Food & Meals → Snack Suggestions**. Ideas come from a curated
library bundled with the app, not an online generative model or your diary.

## Focus behavior

- **High Protein** is always included in the filter: examples include plain
  Greek yogurt, skyr, eggs, edamame, tofu, beans, lentils, seeds, and fish.
- **Fiber**, **Processed Meat**, **Red Meat**, and **Alcohol** add eligible
  suggestions when their focuses are enabled. Their exclusions apply to the
  full filtered list, not just one category.
- Each eligible snack appears once. Small focus badges show every enabled area
  it supports, so a snack can match several focuses without being repeated.
- **Alcohol** shows snack pairings for an alcohol-free break, not foods that
  compensate for alcohol. Disabling a focus removes snacks that only match it.

Rows explain the connection and suggest a portion, without claiming precise
nutrition for an unspecified brand or recipe. Portions are starting ideas, not
prescriptions. The app doesn't know allergies or other dietary restrictions.
Selecting a snack selects that one shared item, regardless of how many focus
areas it matches.

### Nutrition references

The food choices follow general snack guidance from the
[CDC](https://www.cdc.gov/healthy-weight-growth/healthy-eating/meals-snacks.html)
and protein-food examples from
[USDA MyPlate](https://www.myplate.gov/web/web/eat-healthy/protein-foods).
Fiber choices are supported by
[NIH MedlinePlus](https://medlineplus.gov/ency/patientinstructions/000193.htm),
including nuts, legumes, fruit, and whole grains. Reviewed September 25, 2026.
Maintain the explicit meat flags and per-focus explanations when adding ideas;
do not infer that an unclassified food is suitable for an enabled exclusion.

## Reminders workflow

1. Tap **Choose Reminders List** and allow access when iOS asks.
2. Choose an existing writable list. Its identifier is saved on this device;
   use **Change** to choose another. Selecting a list doesn't write anything.
3. Select individual snacks or **Select All**.
4. Tap **Add Selected to Reminders**. Success reports how many were added or
   were already present. Only successful additions clear the selection.

Apple's [EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
requires full Reminders permission for this workflow; it has no Reminders-only
write-only mode. The app includes `NSRemindersFullAccessUsageDescription` and uses
`requestFullAccessToReminders`. Browsing suggestions never asks for permission.

The exporter:

- Only creates new reminders in the explicitly selected list; it never creates
  lists, edits existing reminders, or marks items complete.
- Exports only the snack name and an app link to Log Food. It adds no notes,
  serving tips, dates, alarms, diary entries, personal nutrition data, or focus
  preferences.
- Reads only the chosen list's incomplete reminders when checking duplicates.
  Exact normalized titles (case/spacing/diacritics) or stable app links match;
  synonymous descriptions aren't inferred. Selections are unique.
  Completed or deleted items may be added again for the next shopping trip.
- Stages the batch and commits once. A failed save discards pending changes and
  shows an error; no success is reported. A fetch failure stops the write.
- Revalidates the chosen list on Add. If it was removed or became read-only,
  asks for another choice rather than silently using the default list. Renames
  with the same identifier are picked up without requiring a new choice.

Reminders may sync through the list's configured account. A shared list can be
visible to other people. No reminders or list names are sent to app analytics.
Duplicate checks are best-effort against the fetched snapshot; another app or
device can independently add the same food concurrently.

## Verification

`make test` covers all 16 focus combinations, global meat exclusions, unique
selections, saved list reuse/rename/change, duplicate skipping/restocking, and
permission/read/write failures through an isolated fake Reminders client.
`make ui-test-snacks` checks navigation, selection, and protein-only mode without
requesting Reminders access or writing to a real list.

Before shipping, use a disposable list on an iPhone to check the actual EventKit
permission sheet, denial/re-enabling in Settings, list selection and a successful
write, second-Add deduplication, completed-item restocking, relaunch, renamed or
deleted lists, read-only/shared lists, and no-writable-list state. Also verify
Dynamic Type and dark appearance. Simulator fakes don't prove account sync or
real Reminders writes; no physical-device test is implied by unit-test success.
