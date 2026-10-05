# Custom meal imports

Yum Chase supports one tool-neutral structured nutrition format: `.calmeal`, a
UTF-8 JSON file containing one named meal and one or more complete food
components. A simple food is represented as a meal with one component.

The in-app prompt always requests `.calmeal`. It asks an assistant to estimate
likely added butter, cooking oils, dressings, and sauces when the dish or
preparation makes them plausible. Calorically material additions should be
separate components, with uncertainty described in notes and no ingredient
counted twice. Repeated estimates use a fresh filename based on a normalized
meal-name slug and a unique UUID suffix, ending in `.calmeal`.

## Workflows

### Analyze a photo in Yum Chase

1. In **Settings → Connections → OpenAI API**, add your own OpenAI API key.
   API use has separate billing from a ChatGPT subscription. This direct
   client-key setup is intended for private deployment; a distributed app
   needs an authenticated backend to protect and limit a shared key.
2. In Yum Chase, open **Log food → Analyze a meal photo**, then take or choose
   one photo and optionally describe its portion or preparation.
3. Review the photo and context shown before tapping **Analyze Photo**. Yum Chase
   sends those inputs and fixed meal-estimation instructions directly to OpenAI.
   It does not send diary or HealthKit history. The image is resized, converted
   to JPEG, and stripped of source metadata before upload.
4. Review and edit the estimated components and totals, then explicitly tap
   **Log**. Analysis alone never writes to the diary or Apple Health. The meal is
   logged to the diary day selected when Log food was opened, even if analysis
   crosses midnight.

Each analysis and retry makes one billable request. Cancel stops local waiting
but may not stop provider processing or charges. The app uses the Responses API
with `store: false`; this does not promise zero provider retention. See the
[OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data)
for current platform behavior.

### Import a `.calmeal` file

1. Open **Settings → AI Food & Meal Import** and copy the prompt.
2. Send a food photo and useful context to an assistant, then ask it to follow
   the prompt and return a `.calmeal` attachment.
3. Open or share the attachment to Yum Chase.
4. Review and edit every component and the calculated total. Tap **Log** to add
   one serving to today, and enable Save to Saved meals only when desired.

This separate file-import route remains available; the app receives only the
structured meal file, not the conversation.

## Version 1

A meal contains a name and complete per-component snapshots. The app calculates
meal totals from `foods`; top-level nutrition is intentionally absent.

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
        "proteinGrams": 45,
        "fiberGrams": 2
      },
      "containsProcessedMeat": false,
      "containsRedMeat": false
    },
    {
      "name": "Cooking oil",
      "servingDescription": "about 1 tsp used for this portion",
      "servingGrams": 5,
      "nutrition": {
        "calories": 40,
        "carbohydratesGrams": 0,
        "fatGrams": 4.5,
        "proteinGrams": 0,
        "fiberGrams": 0
      },
      "notes": "Likely used in cooking; amount is uncertain. Chicken nutrition excludes this oil."
    },
    {
      "name": "Quinoa and black beans",
      "servingDescription": "1 cup",
      "servingGrams": 220,
      "nutrition": {
        "calories": 310,
        "carbohydratesGrams": 54,
        "fatGrams": 6,
        "proteinGrams": 13,
        "fiberGrams": 12
      }
    }
  ],
  "notes": "Oil quantity is uncertain and counted only in its own component."
}
```

Each item in `foods` is the exact portion eaten, not nutrition per 100 grams.
Food-specific `notes` may be included on any item. Add butter, oils, dressings,
and sauces as separate components when plausible and calorically material.
Do not add arbitrary fats when preparation does not support them. State
uncertainty and make clear when an ingredient is included in another component.

## Validation and behavior

All fields except `notes`, `fiberGrams`, `containsProcessedMeat`, and
`containsRedMeat` are required. `fiberGrams` is an optional nonnegative number;
when absent, Fiber remains unavailable rather than defaulting to zero. The
optional meat fields are booleans. Omitted values remain unknown until local
catalog/name resolution supplies evidence; they never default to false. Review
offers Automatic/Yes/No, shows inferred values and warns about disagreements
with explicit supplied values. Your explicit choice wins. Resolution preserves
the imported nutrition and portions. Red meat means unprocessed mammalian meat; a
mixed food can set both flags. Numeric fields contain numbers rather than
strings or ranges. `servingGrams` is the estimated weight of the portion
described by `servingDescription`.

The app accepts only the `.calmeal` extension and meal format identifier,
limits a meal to 1–50 foods, caps files at 256 KiB, and rejects malformed JSON,
unsupported versions, blank names or serving descriptions, negative/non-finite
nutrition, and implausibly large values. Former `.calfood` files are unsupported
and rejected without writing to the diary.

A one-off meal logs as one meal entry and retains an imported reusable snapshot
for Recent/quick logging, without joining the hand-created Saved Meals library.
Its components do not become Custom Foods. The diary entry can still be
rescaled and broken apart. SQLite commits the reusable snapshot and entry
atomically. See [Food classification resolution](food-resolution.md) for
matching rules and reviewed historical corrections.

## Assistant prompt

The exact prompt is defined in `CalorieTracker/Models/CustomImportFile.swift` and
exposed in Settings with a Copy Prompt button. It always requests one named
`.calmeal` with one or more food components, including a single component for a
simple food. It requests likely hidden fats and condiments when plausible,
notes uncertainty, avoids double counting, and instructs the assistant to use a
fresh meal-name slug plus unique suffix for every filename.
