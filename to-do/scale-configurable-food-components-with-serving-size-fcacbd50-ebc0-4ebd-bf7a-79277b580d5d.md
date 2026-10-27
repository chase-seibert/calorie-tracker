## User requirements

As a user, I want component calorie amounts and the configured food total to update when I change its serving size, so that the displayed recipe stays internally consistent.

As a user, I want selected defaults, optional additions, and exclusive replacements to affect the configured total exactly once, so that it reflects the choices I see.

Scope: apply this behavior across all configurable food types and option groups, using one shared calculation path. Cappuccino is the root-cause example and a focused regression case, not the limit of the change.

Assumption: component gram amounts describe a reference parent serving and scale with the selected named parent portion (for Cappuccino, the 12 fl oz medium reference); configurable foods without distinct parent sizes retain their current per-serving component amounts. The logged quantity remains a separate multiplier.

## Architecture and data model

Use a single size-aware nutrition model for every configurable food in the customization preview, option calorie labels, configured commits, and variation quick-add. Apply it consistently to included ingredients, optional additions, and exclusive selections regardless of food category. Derive each component amount from its catalog reference amount and the selected parent portion before calculating its nutrients. Keep option labels on a per-parent-serving basis, using the same derived amount as the total; scale the completed serving nutrients by the number of parent servings only after configuration is resolved.

Make the configurable base exclude nutrients represented by selectable components. For Cappuccino, replace the generic whole-drink baseline with a documented component-consistent base, then add the selected milk and other selected options from their size-adjusted amounts. Ensure a default selection is represented once, an unselected option contributes nothing, and an exclusive selection replaces its group peer. Keep the existing frozen option/portion snapshot semantics for history; no diary SQLite schema or Codable migration is expected. Update the catalog source and bundled generated catalog as needed, without changing historical logged snapshots.

## Basic test cases

- Switch Cappuccino among Small (8 fl oz), Medium (12 fl oz), and Large (16 fl oz): every milk/add-in calorie label and the configured total update immediately, and each option label matches its size-adjusted component amount.
- Exercise the same shared scaling behavior on at least one configurable non-beverage food with distinct parent portions, confirming its included/default and optional component labels and total update from its selected portion too.
- For a known reference amount, verify Small and Large component amounts and nutrients scale by the selected parent portion ratio; verify changing the logged serving quantity scales the resolved serving total separately.
- With default Whole milk selected, verify its nutrients are included exactly once. Deselect it and verify they are removed once; the total remains consistent with the milk-free base and any other selected options.
- Replace Whole milk with 2% milk in the exclusive Milk group: the total removes the scaled Whole milk amount and adds the scaled 2% amount once. No other milk selection remains.
- Check Cappuccino totals reconcile to the selected base plus selected size-adjusted components, and cannot fall below the selected milk component alone. Verify an unselected add-in changes only its displayed estimate, not the total.
- Verify configurable foods with no distinct size portions retain current component amounts and existing configuration snapshot/history behavior.

## High-level implementation details

1. Trace `FoodConfigurationCalculator` and `FoodCustomizationView` together so one resolved per-serving component amount drives both option labels and nutrition arithmetic for every configurable food, independent of category. Preserve the separate quantity multiplier and variant behavior, and make exclusive replacement/default removal operate on normalized amounts.
2. Define the size reference for portioned parents (use the medium/default parent portion as the reference where sizes are named) and apply its ratio to option gram amounts consistently across all such foods. Keep selections and the selected portion in the existing configuration snapshot so saved/reopened configurations remain reproducible.
3. Correct Cappuccino catalog data so its base profile does not already include selectable milk; keep the default Whole milk and alternate milk amounts tied to the reference serving. Rebuild the checked-in SQLite catalog through the repository catalog workflow and review any source-generation changes required.
4. Update `FoodCustomizationView` option calorie details to use the same size-adjusted amount as the calculator, while retaining clear per-serving labeling for variants and add-ins.
5. Add focused calculator and view/model coverage in `CalorieTrackerTests/CalorieTrackerTests.swift` for size changes across beverage and non-beverage examples, quantity scaling, default inclusion, exclusive replacement, unchanged single-size behavior, and Cappuccino reconciliation. Verify the bundled catalog fixture values and document any recipe-estimation assumption if the component-free base needs a reviewed nutrition source.

Risks and open decision: Cappuccino’s component-free espresso/foam nutrition and exact milk proportions are estimates. Confirm the intended recipe basis while correcting catalog data; do not preserve a generic whole-drink baseline and also count its milk as a separate selected component.
