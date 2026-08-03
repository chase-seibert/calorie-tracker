# Initial brainstorm

The project began on 2026-08-03 with a request for a lightweight personal iOS
replacement for MyFitnessPal. The central requirement is speed: all routine data
and food search should be local to the phone, with no server-side database.

The initial scope is deliberately narrow. The diary should focus on yesterday,
today, and tomorrow; record calories, carbohydrates, fat, and protein; support
measured quantities and remembered units; and minimize taps for foods eaten
repeatedly. Fast entry should include recent foods, favorites, foods used most in
the last 90 days, barcode scanning, custom foods, and saved multi-food meals.

Excluded features include weight, water, exercise, steps, notes, breakfast/lunch/
dinner categorization, diary completion, recommendations, and micronutrient
detail. A later trends view should chart calories and macros over time.

The food-catalog bake-off has three sources: USDA FoodData Central, Open Food
Facts, and the user's MyFitnessPal history. The first two should be downloaded,
normalized, indexed, and bundled for fully local use. The MyFitnessPal export
will be provided later, so the initial app should include an import seam and make
that history available as a third source once present.

