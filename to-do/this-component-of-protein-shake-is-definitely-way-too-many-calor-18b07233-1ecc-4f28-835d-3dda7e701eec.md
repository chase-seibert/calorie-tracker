## User requirements

As a user, I want the Protein shake component calorie amounts to reflect the actual selected ingredient and serving size, so that an obviously excessive value does not mislead me while customizing a shake.

As a user, I want the displayed component calories and shake total to agree with the same nutrition calculation, so that I can trust the saved configuration.

Scope: investigate and correct the anomalous component shown in the screenshot. It appears to show Almond milk at “2122 kcal” and 2% milk at “+125 kcal” for a 12 fl oz shake. The exact intended Almond milk value and whether the visible number is a data, scaling, or formatting issue must be confirmed against the rendered UI and catalog. Do not infer a replacement value from the screenshot alone.

## Architecture and data model

Trace the catalog component amount and nutrition through `CatalogStore.chaseFoodOptions(for:)`, `FoodConfigurationCalculator.componentAmountGrams`, `FoodConfigurationCalculator.nutrients`, and `FoodCustomizationView.optionPill`. The Protein shake catalog defines Almond milk as 48 kcal per 240 g and its default component amount as 240 g; the shake has 12, 16, and 20 fl oz portions. Confirm the source and generated catalog agree, and check whether the shown option label uses the selected shake portion and the same component amount as the total.

No diary persistence schema or migration is expected: component selections and nutrient snapshots already flow through the existing configuration and diary model. If the root cause is incorrect curated catalog data, update its source and regenerate the bundled catalog while preserving historical logged snapshots. If it is calculation or display logic, correct the shared path so the option estimate and configured total remain consistent.

## Basic test cases

- Open Protein shake at the screenshot’s 12 fl oz portion and confirm Almond milk displays a plausible value derived from its verified component data, not “2122 kcal”; confirm the total reconciles with the selected components.
- Select 2% milk and verify its displayed calories and the configured total use the same 12 fl oz-adjusted component amount.
- Switch among 12, 16, and 20 fl oz portions; verify component amounts and total scale consistently, with no anomalous jump or concatenated/misformatted calorie label.
- Switch between Almond, 2%, whole, oat, and skim milk; verify the exclusive Liquid group contributes only its selected option, and replacing a choice removes the previous contribution.
- Confirm the default protein powder remains included once and optional additions affect the total only when selected.
- Save and reopen the shake configuration; verify the selected portion and components, displayed values, and logged nutrition remain consistent.
- Check an ordinary single-portion configurable food to ensure any shared calculation or formatting fix does not change its component estimates.

## High-level implementation details

1. Reproduce the screenshot state and inspect Protein shake option definitions, selected portion, option label formatting, and total calculation. Compare the source workbook/catalog component grams and nutrient records with the bundled SQLite values to identify the specific failure.
2. Establish the expected component calories from verified catalog nutrition and the 12 fl oz portion ratio; verify the same calculation at 16 and 20 fl oz. Treat a visible “2122” as a possible UI formatting/composition issue until confirmed.
3. Fix the narrowest responsible layer. If source values are wrong, correct the authoritative catalog input and regenerate the bundled SQLite using the repository catalog workflow. If amount scaling, normalization, or formatting is wrong, update the shared calculator/view path so labels and totals use one per-serving component amount.
4. Add focused regression coverage in `CalorieTrackerTests/CalorieTrackerTests.swift` for the screenshot state, portion scaling, exclusive milk replacement, default protein powder, and total reconciliation. Include a boundary case with a non-scaled food if shared logic changes.
5. Run the relevant catalog checks and iOS build/test workflow for an implementation; inspect generated diffs and confirm historical diary snapshots need no migration. Open decision: the screenshot’s Almond milk text may combine a portion/count with the calorie value; confirm its exact intended presentation during reproduction.
