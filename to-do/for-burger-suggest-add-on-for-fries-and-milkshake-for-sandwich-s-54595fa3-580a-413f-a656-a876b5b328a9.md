# Burger and sandwich companion food suggestions

## User requirements

- As a user, I want to know whether an option changes the food I selected or adds another food beside it, so that the diary represents what I ate without blending separate foods together.
- As a user, I want ingredients, toppings, condiments, and recipe variants to remain part of the configured food, so that their nutrition and choices are saved with that food.
- As a user, I want independently identifiable accompaniments to be suggested as optional companion foods, so that I can log each one with its own identity, portion, nutrition, and later edit or remove it separately.
- As a user, I want to choose which suggestions to log, so that suggestions never silently add food or change the configured food's nutrition. Logging a main food and selected companions together may be one action, but the diary must retain separate entries and count each item's nutrition once.
- As a user, I want these distinctions to apply consistently across foods, so that similar choices behave the same way wherever they appear.
- For this task, apply the behavior to canonical Burger and Sandwich: suggest Fries and Milkshake with Burger, and Chips with Sandwich. Keep cheddar and mayonnaise as configured ingredients. Assumptions: “chips” means the Potato chips canonical food; no companion is selected by default; use each companion's normal remembered/default portion.

**Brainstormed examples for future consideration (not added to this task's scope):**

- Pizza: extra cheese and pepperoni are part of the configured pizza; wings or a side salad are separate foods.
- Soup: croutons can be part of the configured soup; bread or crackers can be separate accompaniments.
- Hot dog: relish, mustard, and cheese are part of the hot dog; fries or a drink are separate foods.
- Pancakes: syrup or berries can be configured toppings; eggs or sausage can be separate breakfast foods.
- Tacos: salsa and cheese can be part of the configured taco; rice or beans can be separate side dishes.

## Architecture and data model

- The bundled Chase Food catalog currently represents Burger's Fries as a `chase_food_options` row with relationship `Suggested addition`. `FoodDetailView` includes selected options in `configuredComponents`, its nutrition total, the food configuration snapshot, and saved variations. That makes Fries part of the configured Burger today.
- Keep recipe components in the existing food-option model. Represent companion recommendations separately as relationships between stable parent-food and companion-food IDs, with display order. For this task, define Burger → Fries, Burger → Milkshake, and Sandwich → Potato chips. Extend the catalog build/load path (`scripts/build_food_catalog.py` and `CatalogStore`) to expose the companion relationships without duplicating food identity or nutrition. Keep cheddar and mayonnaise in the existing option data.
- Render companion choices separately from ingredient and variant controls in `FoodDetailView`. They must not contribute to the primary food's configured nutrients, `FoodConfigurationSnapshot`, or `SavedFoodConfiguration`.
- Log the primary food and selected companions through one `DiaryStore` day-scoped write, with `DiaryEngine` creating an ordinary independent `DiaryEntry` for each companion using its normal portion preference. This avoids a partial meal if persistence fails. Existing entry and nutrient-total behavior then accounts for each row normally.
- No diary schema or history migration is needed. Preserve already logged snapshots as recorded. Handle older saved Burger variations that captured Fries so using one cannot silently fold Fries into a new Burger log.

## Basic test cases

- Open canonical Burger customization: Fries and Milkshake appear as optional companion foods; Sandwich-only Chips do not appear.
- Log Burger without selecting companions: one Burger entry is created, and its nutrients contain only the Burger and selected ingredients.
- Select Fries and Milkshake and log Burger: three independent entries appear for the same date; each side has its own food identity, quantity, and nutrients, and the diary total includes all three exactly once.
- Configure Burger with cheddar or Sandwich with mayonnaise: those additions remain in the primary configured entry and affect its nutrient total; selected companions remain separate rows.
- Open canonical Sandwich customization: Chips appears as an optional companion; Fries and Milkshake do not.
- Cancel or leave companion choices unselected: no companion entry is created. A failed combined write leaves neither the primary nor companion entries partially logged.
- Edit or remove a companion entry: the parent food's configuration and nutrition remain unchanged.
- Open an older logged Burger snapshot or saved variation containing Fries: historical nutrition stays unchanged, and reusing the variation does not silently log Fries as a Burger ingredient.

## High-level implementation details

1. Update the Chase Food catalog source/build output to remove Fries from Burger's `Suggested addition` options and add the three stable-ID companion relationships. Confirm the selected Chips identity and labels against the bundled catalog.
2. Add a read API in `CatalogStore` for companion recommendations, resolving names, portions, and nutrition through the existing bundled food records.
3. Add a separate optional companion-selection section to `FoodDetailView`. Keep selection state and portion defaults separate from ingredient choices, saved configurations, and the primary food's live macro calculation.
4. Add a single day-scoped `DiaryStore` operation that logs the configured primary food and selected companion foods in the same repository transaction. Reuse normal food logging and quantity preferences so each companion is independently editable in the diary.
5. Add compatibility handling for previously saved Burger variations that contain Fries, without rewriting historical diary snapshots. Update the food-taxonomy documentation with the general distinction between configured components and separate companion foods; include only Burger and Sandwich as this task's implemented pairings.
6. Add focused catalog, customization, atomic-logging, nutrient-total, independent-edit, and legacy-variation coverage; then run the repository's `make test` with host-side simulator access and attempt `make phone-deploy`, reporting build, installation, launch, and device blockers separately.

The general boundary is whether a choice is part of the food's recipe/variant or remains an independently recognizable food. Some choices depend on context (for example, berries can be a topping or a separate side); define their role per food while keeping this task's listed examples explicit. The catalog also has Potato chips and Tortilla chips, so this plan assumes Potato chips for generic Sandwich.
