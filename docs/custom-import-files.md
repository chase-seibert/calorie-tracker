# Custom food and meal imports

Calorie Tracker owns two small, tool-neutral formats for structured nutrition
estimates. Both are UTF-8 JSON:

- `.calfood` represents one aggregate food serving.
- `.calmeal` represents one named meal containing a list of food servings.

ChatGPT, another assistant, or a hand-written tool can produce either format.
The in-app prompt defaults to `.calfood`; it selects `.calmeal` only when the
user explicitly requests a meal file or separate foods.

## Workflow

1. Send a food photo and any useful context to an assistant.
2. In Calorie Tracker, open **Settings → AI food & meal files** and copy the
   format prompt.
3. Paste the prompt after the assistant analyzes the food. Explicitly request a
   meal file or separate foods only when that is desired.
4. Open or share the returned attachment to Calorie Tracker.
5. Review and edit every value. Tap **Log** to add one serving to today.
6. Enable the save toggle only when the food or meal is worth reusing.

The conversation is not shared with Calorie Tracker. Only the structured import
file crosses the boundary.

## `.calfood` version 1

This is the default format and represents the entire pictured portion as one
food:

```json
{
  "format": "calorie-tracker-food",
  "version": 1,
  "name": "Buffalo chicken salad",
  "servingDescription": "whole bowl",
  "servingGrams": 510,
  "nutrition": {
    "calories": 750,
    "carbohydratesGrams": 32,
    "fatGrams": 40,
    "proteinGrams": 60
  },
  "containsProcessedMeat": false,
  "containsRedMeat": false,
  "notes": "Dressing and buried cheese are the biggest uncertainties."
}
```

## `.calmeal` version 1

A meal contains a name and complete per-food snapshots. The app calculates meal
totals from `foods`; top-level nutrition is intentionally absent.

```json
{
  "format": "calorie-tracker-meal",
  "version": 1,
  "name": "Chicken grain bowl",
  "foods": [
    {
      "name": "Chipotle chicken",
      "servingDescription": "6 oz portion",
      "servingGrams": 170,
      "nutrition": {
        "calories": 300,
        "carbohydratesGrams": 4,
        "fatGrams": 12,
        "proteinGrams": 45
      },
      "containsProcessedMeat": false,
      "containsRedMeat": false
    },
    {
      "name": "Quinoa and black beans",
      "servingDescription": "1 cup",
      "servingGrams": 220,
      "nutrition": {
        "calories": 310,
        "carbohydratesGrams": 54,
        "fatGrams": 6,
        "proteinGrams": 13
      }
    },
    {
      "name": "Cheese and tomatillo-avocado salsa",
      "servingDescription": "toppings",
      "servingGrams": 90,
      "nutrition": {
        "calories": 190,
        "carbohydratesGrams": 10,
        "fatGrams": 13,
        "proteinGrams": 8
      }
    }
  ],
  "notes": "Cooking oil and the exact chicken and quinoa portions are the biggest uncertainties."
}
```

Each item in `foods` is the exact portion eaten, not nutrition per 100 grams.
Food-specific `notes` may be included on any item. Oils, dressings, and sauces
should be separate foods when they are calorically material.

## Validation and behavior

All fields except `notes`, `containsProcessedMeat`, and `containsRedMeat` are
required. The optional meat fields are booleans, default to false when absent,
and remain editable in the review screen. Red meat means unprocessed mammalian
meat; a mixed food can set both flags. Numeric fields contain numbers rather
than strings or ranges. `servingGrams` is the estimated weight of the portion
described by `servingDescription`, preserving meaningful food-weight reports.
Fiber is intentionally absent because the app does not currently track it.

The app validates that extensions and format identifiers agree, limits a meal to
1–50 foods, caps files at 256 KiB, and rejects unsupported versions, blank names
or serving descriptions, negative/non-finite nutrition, and implausibly large
values. A `.calmeal` using the former aggregate-food shape is invalid; that
shape now belongs exclusively to `.calfood`.

A one-off `.calfood` logs without adding a Custom Food. A one-off `.calmeal`
logs as one meal entry containing component snapshots without adding a Saved
Meal or Custom Foods. The diary entry can still be rescaled and broken apart.

## Assistant prompt

The exact combined prompt is defined in
`CalorieTracker/Models/CustomImportFile.swift` and exposed in Settings with a
Copy Prompt button. Its decision rule is deliberately first and explicit:

1. Default to one `.calfood`.
2. Use `.calmeal` only when the user explicitly requests a meal file or separate
   foods.
3. Never create both.
