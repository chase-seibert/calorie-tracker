# Initial brainstorm

The project began on 2026-08-03 with a request for a lightweight personal iOS
calorie tracker. The central requirement is speed: all routine data and food
search should be local to the phone, with no server-side database.

The initial scope is deliberately narrow. The diary should focus on yesterday,
today, and tomorrow; record calories, carbohydrates, fat, and protein; support
measured quantities and remembered units; and minimize taps for foods eaten
repeatedly. Fast entry should include recent foods, favorites, foods used most in
the last 90 days, barcode scanning, custom foods, and saved multi-food meals.

Excluded features include weight, water, exercise, steps, notes, breakfast/lunch/
dinner categorization, diary completion, recommendations, and micronutrient
detail. A later trends view should chart calories and macros over time.

The food-catalog bake-off has two sources: USDA FoodData Central and Open Food
Facts. Both should be downloaded, normalized, indexed, and bundled for fully
local use. Personal foods should remain in the writable on-device store.
