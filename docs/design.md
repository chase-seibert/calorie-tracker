# Design

## Principles

1. The default screen answers “what have I logged today?” immediately.
2. Repeated-food flows optimize for one tap; search results use a lightweight
   quantity sheet before logging when an amount has not yet been remembered.
3. Only calories, carbohydrates, fat, and protein are visually prominent.
4. Source identity is visible but quiet, making the dataset bake-off possible
   without cluttering routine use.

## Navigation

- **Diary**: date strip, macro summary, entries, and a prominent add button.
- **Trends**: calorie and macro daily charts.
- **Settings**: source counts, data attribution, import, and data management.

The Custom source row in Settings shows separate food and meal counts and opens
a personal catalog with Custom Foods and Saved Meals sections.

The add-food sheet wraps all modes into visible rows: Recent, Frequent,
Favorites, Meals, Search, Scan, and Custom. Search provides a compact USDA / Open
Food Facts / MyFitnessPal source switch. Quantity entry starts in ounces for a
new food and offers every natural portion retained from the source dataset.
Search, recent, frequent, and favorite rows display the remembered amount and
portion when one exists, including its scaled calories.

Saving a meal enters a selection mode in the diary. The user explicitly checks
one or more entries, names the combination, and leaves unrelated foods out.

## Visual language

The app uses a warm off-white background, a coral calorie accent, and blue,
violet, and green macro accents. Rounded cards provide hierarchy without turning
the diary into a dashboard of unrelated features.
