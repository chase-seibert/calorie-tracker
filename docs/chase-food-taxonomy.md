# Chase Food taxonomy and source

**Status:** Product direction and first-pass implementation. This document
records the requested behavior, taxonomy decisions, and current catalog shape.

## Purpose

Chase Food is a curated, local food catalog for Yum Chase. It gives the app a
small, recognizable vocabulary that is quick to search and easy to customize.
It is a separate data source alongside USDA and Open Food Facts, so the user can
evaluate Chase Food on its own.

The workbook is [Canonical U.S. Food Taxonomy — Review Draft](https://docs.google.com/spreadsheets/d/16Y1Uc0jldJ4tGO_vf5mgjT0n8pwJxO13W54zR5M_wWo/edit).
The preceding [Canonical Food List Criteria conversation](https://chatgpt.com/share/6ace459c-9910-83e8-b7db-44bcaa4894be)
provides the rationale and initial model. The current review dataset has 532
catalog identities (487 search-enabled), 1,934 portion mappings, 1,223 alias
records, 494 configurable options/components, 25 companion-food pairings, and
28 presets. Portion and option amounts are first-pass estimates; nutrition
records include reviewed source portions, confidence, and preparation notes.
The 2026-10-20 revision adds a single Kebabs search identity with exclusive
lamb, chicken, and beef protein variants; the former Lamb kebab and Beef kebab
IDs remain history-resolvable and serve as reusable variant components. The
2026-10-23 revision adds nutrition evidence for 20 more searchable identities.
Companion suggestions are separate foods logged independently. The generated
review workbook is rebuilt from the same catalog projection.

The [Bagel customization concept](chase-food-bagel-concept.pdf) documents the
single canonical Bagel result, portion-aware bagel type choices, and optional
spreads. The former Bagel with cream cheese ID remains history-only so old diary
entries continue resolving; its search aliases now point to Bagel.

The personal-food coverage pass also reviewed [Chase Seibert's Cookbook](https://chase-cookbook.s3.us-west-2.amazonaws.com/cookbook.html),
last updated September 15, 2026. Cookbook recipe titles should usually become
search aliases, saved configurations, or reusable ingredients rather than
separate canonical foods. The mapping below is a first editorial pass, not a
claim that recipe nutrition is already measured.

## Product principles

1. **Recognize the food first.** Search resolves familiar wording to one stable
   canonical food identity. Names such as “hamburger” and “smash burger” can
   resolve to “Burger”; the result remains the canonical food.
2. **Keep identity separate from composition.** A burger is one food identity.
   Cheese, bacon, and mayonnaise configure the burger; fries and a milkshake
   are optional companion foods with their own diary entries. Presets such as
   “Bacon cheeseburger” can be convenient selections built from reusable
   ingredient identities.
3. **Make a reasonable default fast.** A user can add the canonical food with
   its default portion in one action. Customization is optional.
4. **Show only useful search information.** Chase Food results show the
   canonical food name and a quiet “Chase Food” source badge. Do not show the
   taxonomy category or food kind in search results. Aliases help match queries;
   the canonical name remains the selected item. A matched alias may appear as
   a subtle “Matched: …” hint when useful.
5. **Preserve history across source changes.** A source toggle controls which
   catalog items appear in new search results. Turning a catalog off does not
   delete it, hide its existing diary rows, change their nutrition, or unlink
   their stable source identity. Diary snapshots continue to resolve to the
   original source item.
6. **One identity, one nutrition path.** Standalone foods, additions, and
   presets should reference the same reusable food records. A logged entry
   retains the nutrition values used when it was logged, even if the catalog is
   revised later.
7. **Treat precision honestly.** The workbook's human portions and proposed
   compositions are estimates pending review. Nutrient values must be populated
   from an authoritative source or otherwise verified before they are treated
   as production values.
8. **Reserve quick controls for meaningful nutrition changes.** Show an
   ingredient as a quick choice when a usual serving materially changes the
   configured food. Keep unlisted ingredients available through Add ingredient
   when useful. Curate separate companion suggestions per parent food rather
   than assuming every side is appropriate everywhere.
9. **Keep brand searches generic and label evidence separate.** Map cereal
   brands to the closest generic food or to Cereal when the current types do
   not fit. Store manufacturer label values as research evidence with product,
   serving size, date, and source; do not use them as generic nutrition values
   or imply that an alias has brand-specific nutrition.
   The initial cereal comparison is checked in at
   `data/chase-food/cereal-brand-research.json` and appears as the **Cereal
   Brand Research** tab in the review workbook.
10. **Classify choices by how people recognize and log them.** Treat an item as
    part of the configured food when it changes that food's recipe, variant,
    topping, or condiment (for example, cheddar on a burger or mayonnaise on a
    sandwich). Treat it as a companion when it remains a recognizable food in
    its own right, has its own portion and nutrition, and a user could sensibly
    edit or remove it independently. Context matters: berries can be a yogurt
    topping or a separate side depending on the parent food and intended use.
    Define the relationship for each parent instead of assigning a universal
    role to an ingredient.
11. **Scale configured ingredients with the parent quantity.** Every included
    ingredient and optional topping amount describes the amount for one
    explicitly defined parent serving. The full logged quantity determines how
    many parent-serving equivalents to apply, whether the user enters slices,
    ounces, grams, cups, or another supported portion. Never use a component's
    entire default serving as a topping amount just because its recipe amount
    was left unspecified. Every configurable option must have an explicit
    `Amount (g)` in the workbook; catalog compilation rejects missing or
    nonpositive amounts instead of silently substituting the component's
    standalone serving size. For exclusive full-food substitutions, use the
    amount of that component within one parent serving.

## Source controls

Settings → Food & Meals → Food Data Sources should show independent controls
for the local catalogs:

| Source | Intended control |
| --- | --- |
| USDA | Include/exclude USDA foods in search |
| Open Food Facts | Include/exclude packaged-food records in search |
| Chase Food | Include/exclude the curated canonical catalog in search |

The requested bake-off setup is Chase Food on, USDA off, and Open Food Facts
off. The controls should be source filters on search; they should not erase
catalog records or alter existing diary entries. Personal foods and saved meals
remain in the personal library and are not local catalog toggles.

## Search behavior

- Search the canonical display name and its approved aliases.
- Return a canonical food once even when several aliases match it.
- Preserve the alias-to-food mapping as data so aliases can be corrected without
  duplicating foods or nutrient profiles.
- Show the canonical name, source badge, and the normal serving/calorie summary.
  Omit category and food kind.
- Keep source enablement independent: a disabled source contributes no results;
  enabled sources continue to search together.
- A result offers a direct-add action and a customization action. Direct add
  uses the default portion and keeps the orange plus button on the far right as
  the primary action. A quieter pencil button labeled Customize sits immediately
  to its left. Tapping the rest of the result row also opens customization.
- A canonical result may expand to show the user's saved configurations beneath
  it. Group those variations with the canonical result, similar to grouped
  suggestion sets. Each variation has its own trailing plus action.

## Saved configurations

When the user customizes a food and adds it, log the configured selection and
save that configuration as a reusable variation beneath its canonical food.
For example, Burger can remain one canonical result while “Cheese, bacon · no
bun” appears under it as a personal variation. The user can add the base food,
open customization again, or add a saved variation directly.

A variation references the base food and reusable component IDs, including
exclusive selections and removed defaults. It does not create another canonical
food or duplicate the component nutrition record. Keep a stable variation ID
and the nutrition snapshot on each diary entry so later catalog edits do not
rewrite history.

## Customizing ingredients and choices

- Show default ingredients in an **Included** section with selected controls.
  Tapping an included item removes it; Burger starts with its bun included.
- Show optional ingredients, variants, and included components in the food's
  configuration. A configured component contributes to that food's nutrition
  and remains part of its saved variation and diary snapshot.
- Show curated companion recommendations in a separate optional section. A
  selected companion keeps its own food identity, portion, nutrition, and diary
  entry; it does not change the primary food's configured nutrition, snapshot,
  or saved variation. Leave companions unselected by default. When the user
  logs the parent and companions together, write ordinary separate diary
  entries for them as one atomic action so a failure cannot leave a partial
  group.
- Offer **Add ingredient** where the catalog can provide useful options. It
  opens food search; choosing a food adds its stable identity to this
  configuration and makes the configuration available as a saved variation
  after logging.
- Model choices such as bread type, cereal type, sauce, milk type, and yogurt
  type as mutually exclusive selections. Use a compact menu/dropdown when a
  list is long, and chips for a short list.
- Model bagel type as a nutrient-bearing variant of the canonical Bagel. A
  selected type replaces the base profile at the current portion weight and is
  retained as a constituent of the logged item; optional spreads such as cream
  cheese add their own portioned nutrition.
- Let each screen combine portion controls with the food-specific choices. For
  coffee, show “Medium · 12 fl oz” so the size label and amount are both clear.
- Keep calories and all three macros live as portion, included items, and
  additions change.
- Define each included ingredient and optional addition as a component amount
  per parent serving, then multiply that amount and its nutrients by the
  quantity of parent servings being logged. Convert weight and other supported
  units to parent-serving equivalents using the selected parent portion before
  scaling. A component's own catalog serving is only its nutrient reference;
  it does not define how much belongs on the parent food.
- When parent portion sizes represent different physical sizes (for example,
  small and large slices), specify component amounts for each size or a clear
  scaling rule. Do not assume a topping amount for one slice fits every slice
  size. Keep independently logged companion foods on their own portions.

## Classifying future food choices

Apply the relationship test to each parent food when curating additions:

- If a choice changes the selected food's recipe or recognizable variation,
  model it as an included component, optional ingredient, topping, condiment,
  or exclusive variant. Its nutrients belong to that food.
- If it is still a recognizable food with its own portion and nutrient record,
  and people may edit or remove it independently, model it as an optional
  companion recommendation. Its nutrients belong in its own diary entry.
- If either role is plausible, use the eating context and logging intent to
  decide, then record that decision for the specific parent. The same food may
  have different roles in different contexts.
- Add companion pairings only when they are useful recommendations for that
  parent. Pairings are opt-in and do not imply a default serving or change the
  parent food's nutrition. Reuse stable catalog food IDs and each companion's
  normal portion/nutrition source; do not create duplicate foods or calorie
  deltas. Current pairings include Burger with Fries and Milkshake, Sandwich with
  Chips, Taco and Hard-shell taco with Refried beans and Rice, Fried fish with
  Fries, Eggplant Parmesan with Pasta, Hummus with vegetable dippers, Kebabs
  with Pita bread, Hummus, and Rice, Lo mein with Spring roll and Fried rice,
  and Meatball sub with Fries, Salad, and Chips. Foods without a useful
  companion recommendation keep no companion rows.

Examples to guide future review, not blanket catalog assignments: extra cheese
or pepperoni can configure Pizza while wings or a side salad can accompany it;
croutons can configure Soup while bread or crackers can accompany it; relish,
mustard, or cheese can configure a Hot dog while fries or a drink can accompany
it; syrup or berries can top Pancakes while eggs or sausage can accompany them;
and salsa or cheese can configure Tacos while rice or beans can accompany
them. Confirm each pairing with the food's intended use before adding catalog
data. The pairings currently implemented also include Kebabs → Pita bread, Hummus,
and Rice; Lo mein → Spring roll and Fried rice; and Meatball sub → Fries, Salad,
and Chips. USDA Pork, carnitas → Mexican rice and Black beans remains a
source-qualified pairing.
A companion parent may come from USDA or Chase Food; source-qualify non-Chase
parent IDs so recommendations attach to the existing catalog identity without
duplicating the food.

## Size and food-specific directions

- **Burger:** Include a bun by default. Offer one exclusive protein choice—beef,
  chicken, or bean—with beef selected by default; users can clear the selection
  for a patty-free burger. Offer cheese, bacon, mayonnaise, and ketchup as
  configured additions; Fries and Milkshake are separate companion foods. Keep garnish
  ingredients out of quick controls; they remain searchable through Add
  ingredient. Use a visual size cue as well
  as weight: draft cues could be a small slider/hockey-puck-scale patty, a
  standard roughly 4-inch patty, and a larger roughly 5-inch patty. Review
  diameter and cooked weight before assigning nutrition.
- **Pizza:** A serving is one slice. Size choices describe the pizza's diameter
  (for example, a slice from a 12-, 14-, or 18-inch pizza), with the number of
  cuts stated because diameter alone does not define slice area. The base
  profile represents prepared cheese pizza, including its sauce and cheese;
  do not add those ingredients a second time as included components. Crust
  styles use complete prepared-pizza nutrient profiles as mutually exclusive
  variants, not crust-only foods as calorie additions. Specify topping grams
  per parent slice and scale them with the logged slice or weight quantity. A
  proposed first quick set is pepperoni, sausage, mushrooms, extra cheese,
  onion, and green pepper; consider olives, bacon, ham, chicken, pineapple,
  and jalapeños as searchable additions. This is a review list, not a measured
  popularity ranking.
- **Omelet:** Include ham with cheese, bacon, and vegetables. Add ingredient
  search for items such as kielbasa so a selected ingredient is retained in the
  logged item and in a reusable variation.
- **Pasta with sauce:** Use a broad screen for sauced pasta, with sauce and
  portion choices plus add-ons such as meatballs, broccoli, sausage, olive oil,
  or parmesan. This covers marinara and combinations such as orecchiette with
  broccoli and sausage. Add ingredient search for less common foods. Keep
  **Lasagna** as its own canonical food and customization screen.
- **Toast:** Include a mutually exclusive bread type such as white, wheat, or
  rye; then allow optional toppings such as butter, peanut butter, or jam.
- **Cereal:** Display the canonical name **Cereal**. Use a natural cup amount
  and a mutually exclusive cereal-type selector. Common cereal names and
  brands can be searchable aliases or choices without multiplying generic
  canonical identities. Map Cheerios varieties to oat-ring cereal, Frosted
  Flakes to frosted corn flakes, and Raisin Bran to bran flakes; route brands
  without a close generic type (such as Lucky Charms, Froot Loops, Cocoa Puffs,
  Cinnamon Toast Crunch, and Special K) to Cereal. Keep brand label values in
  the separate research ledger, not in generic nutrition profiles.
- **Coffee:** Display the canonical name **Coffee**. Use cup sizes with the
  fluid-ounce amount shown. Milk type (for example, 1%, 2%, or whole) is
  mutually exclusive; sugar and cream are optional additions.
- **Yogurt:** Display the canonical name **Yogurt**. Offer a mutually exclusive
  type such as plain, Greek, or low-fat, then reusable additions such as
  berries, granola, honey, or banana.
- **Cappuccino:** Give Cappuccino its own canonical entry, separate from Coffee.
  Use cup sizes with the ounce amount shown and an exclusive milk selector
  (whole, 2%, 1%, skim, almond, or oat); 1% milk is a selectable option.
  Espresso and foamed milk define the base. Sugar, cocoa, or cinnamon can be
  optional. This is a personal staple.
- **Protein shake:** Use the existing canonical Protein shake entry. Start with a
  serving of protein powder and a selectable liquid (almond, 2%, or whole milk),
  then offer peanut butter, banana, and coconut oil. Useful additional choices
  to consider are oats, Greek yogurt, berries, cocoa, and honey. Protein powder
  brand and scoop size need explicit data because nutrition varies widely.
  Keep creatine outside the food catalog as a separately logged supplement;
  it should not add calories or macros by assumption.
- **Sandwich:** Use one canonical Sandwich entry with exclusive filling choices
  such as turkey or tuna, and exclusive bread choices (white as the suggested
  default, plus wheat, rye, and sourdough). Mayonnaise is a common optional
  spread; cheddar, lettuce, tomato, mustard, and pickles are other reusable
  additions. A saved variation can remember the user's usual white-bread,
  mayonnaise, and filling selections.

## Cookbook coverage map

The cookbook contains named recipes, components, dressings, and staples. This
map keeps canonical search focused while retaining useful recipe language as
aliases or saved configurations.

| Cookbook material | Chase Food treatment |
| --- | --- |
| Caesar Salad | Own canonical **Caesar salad**; dressing, croutons, and extra parmesan are choices. |
| Anne's Spinach Salad; Kick-Ass Kale Salad; Quarantine Salad with warm Brussels and Feta | Search and log as **Salad** with optional ingredients such as spinach, kale, egg, bacon, edamame, feta, or Brussels sprouts. Keep recipe names as aliases only if useful. |
| Potato Salad | Own canonical **Potato salad**. |
| Couscous Salad; Brown Rice Salad; Panzanella | **Salad** or a saved salad variation; retain grain/bread and dressing as choices if users need them. |
| Southwest Caesar Salad | Exclude as a standalone catalog food; its base can be Caesar salad, with steak and toppings added when desired. |
| Salad Dressings; Secret Sauce; vinaigrettes; adobo; chili oil; pickles; stock; plum jam/preserves | Reusable condiments, ingredients, or recipe data. Do not create meal-sized canonical food results for these. |
| Drive-Thru Burgers | **Burger** with saved composition/alias; restaurant terms should not imply exact branded nutrition. |
| Taco Night; Red Chile Chicken Enchiladas; Bean and Cheese Tomatillo Enchiladas | **Taco** for taco night, with one exclusive protein choice and meaningful toppings; offer refried beans and rice as separate optional companions. Keep low-impact toppings out of quick controls. Enchiladas can share an **Enchiladas** entry with a filling choice if users log them often. |
| Neopolitan Pizza; Deep Dish Pizza | **Pizza** with mutually exclusive style choices such as Neapolitan/thin crust and deep dish. Search for “deep dish pizza” returns Pizza with Deep dish selected. |
| Baked Ziti; Broccoli Sausage Orecchiette; Garlic Chili Pasta; Pasta e Ceci; Aperto's Tagliolini Pepati; Pasta Cacio e Uova | Use **Pasta with sauce** and saved configurations/choices for pasta shape, sauce, meatballs, broccoli, sausage, chickpeas, or olive oil. Keep **Lasagna** as its own canonical entry. |
| Noel's Chili | Own **Chili** entry; exclusive beef, turkey, or vegetarian type, plus rice, sour cream, and cheese. |
| Beef Stew | Own **Beef stew** entry. |
| Chicken Parmesan | Own **Chicken Parmesan** entry; **Pasta with sauce** can be logged alongside it as a related food. “Chicken parmesan pasta” can be a saved combined configuration. |
| Chicken Piccata; Orange Chicken | Own **Chicken piccata** and **Orange chicken** entries. |
| Thanksgiving Dinner; Turkey; Green Bean Casserole; Stuffing; Gravy; Mashed Potatoes | **Roast turkey** is the main entry, with “Thanksgiving turkey” and “Thanksgiving” as aliases. Keep mashed potatoes, stuffing, gravy, and green bean casserole as separate reusable foods that can be added together. |
| Beef Pot Roast; South Carolina Pulled Pork; Roast Chicken and Green Beans; Pot Roast; Chicken Kebabs | Candidate common entries **Pot roast**, **Pulled pork**, **Roast chicken**, and **Chicken kebab** if coverage warrants; green beans are a related food. Use recipe names as saved variations rather than one record per recipe. |
| Macaroni and Cheese; Cream of Mushroom and Chicken; Louisiana Hot-links and Lentils; Fiery Green Beans and Tofu; Vermicelli Bowl; Pho; Pork Ramen; Chicken Pot Pie; Yellow Curry; Thai Cashew Chicken; Pad See Ew; Braised Chicken Thighs with Black Bean Rice | Map to broad familiar foods (macaroni and cheese, chicken casserole, lentil dish, tofu with vegetables, noodle bowl/soup, curry, chicken with rice, or pot pie) only where the catalog needs them. Keep recipe names as aliases or configurations, not automatic one-for-one canonicals. |
| Burnt Cheesecake | Search as **Cheesecake** if useful; do not offer burnt style as a variation. |
| Pancakes; Christmas Morning Casserole; Ham and Scalloped Potatoes; Horseradish-Crusted Beef Tenderloin; Bread; Flatbread; Prosciutto Cheese Bread; Banana Muffins; Cinnamon Rolls; Biscuits; Yellow Cake; Omelet | **Pancake** is a canonical food. The other dishes fit an existing casserole, ham, scalloped potatoes, beef roast, bread, muffin, cinnamon roll, biscuit, cake, or omelet identity; add distinct entries only when search coverage demonstrates a need. |
| Cocktails; Whiskey Sour; Paloma; Margarita; Negroni; Popcorn; Raspberry Lime Rickey; Ocean Park's Famous Ham and Cheese Italian | Treat as beverages/snacks/sandwiches through their broad canonical foods and ingredient selections; specific recipes can be saved configurations. |

The explicitly requested initial cookbook additions are Caesar salad, Salad, Potato salad, Lasagna, Chili, Beef stew, Chicken Parmesan, Chicken
piccata, Orange chicken, Roast turkey, Cheesecake, and Pancake. The PDF includes
screen concepts for these foods and the three personal staples. Other
cookbook-inspired candidates above can follow after search testing establishes
which ones deserve first-class coverage.

## Food customization

Selecting **Customize** opens a full-screen screen. A back arrow and canonical
food name stay pinned above the scrolling choices, followed by calories, the
carbohydrate, fat, and protein totals, and their stacked horizontal macro bar.
The ungrouped ingredient choices begin in a two-column **Add to this food or
meal** grid; **Add another food** opens a dedicated catalog search screen.
Specialized option groups follow and retain their single- or multiple-selection
behavior as two-column, tap-to-toggle pills. A collapsed **Suggest a change**
link opens its own editor screen. Fries and similar foods keep their own
reusable identity when logged alongside another food.

A pinned quantity card offers the food's portion sizes plus ounces and grams;
changing between weight units preserves the entered mass, and quantity can be
adjusted directly. Calories remain with the pinned macro summary, and a single
**Log Food** button sits below the quantity card.

Configured ingredient amounts are relative to the parent food. For example,
Pizza toppings are specified as grams per slice (or per another defined pizza
portion); logging several slices or entering a weight equivalent to several
slices scales each selected topping by that same parent-serving count. The
catalog must not assign a full serving of mushrooms, sausage, or onion to each
slice unless that amount is explicitly supported by the recipe. The same rule
applies to options on foods logged by weight, volume, count, or named portion.

For Burger, the first concept exposes size plus cheese, bacon, and fries. Fries
remain a separately reusable food, even when selected from the burger screen.
The selection should not silently include optional toppings in the base burger.
The exact default recipe, portion weights, and component amounts need review.

## First ten concept foods

The PDF concept packet covers the eight requested starting examples, two
suggested foods (Banana and Yogurt), three personal staples, and twelve
cookbook-driven canonical foods.

| Concept label | Workbook canonical value | Stable draft ID | Default human portion |
| --- | --- | --- | --- |
| Burger | Burger | \`food_burger\` | 1 burger |
| Pizza | Pizza | \`food_pizza_slice\` | 1 slice |
| Omelet | Omelet | \`food_omelet\` | 1 omelet |
| Taco | Taco | \`food_taco\` | 1 taco |
| Pasta | Pasta with sauce (proposed canonical) | Proposed: \`food_pasta_with_sauce\` | 1 plate |
| Toast | Toast | \`food_toast\` | 1 slice |
| Cereal | Cereal | \`food_cold_breakfast_cereal\` | 1 cup |
| Coffee | Coffee | \`food_black_coffee\` | 1 cup |
| Banana (suggested) | Banana | \`food_banana\` | 1 banana |
| Yogurt (suggested) | Yogurt | \`food_plain_yogurt\` | 1 cup |

The broader display names Cereal, Coffee, and Yogurt now appear in the
workbook while retaining their original stable IDs. Pasta with sauce remains a
proposed broader identity; it replaces the initial Penne pasta with sauce
concept, while Lasagna stays separate.

## Brand and restaurant aliases

Support common restaurant and packaged-food names as searchable aliases when
they identify a known food or variation. For example, relevant burger queries
may include Five Guys, McDonald's, and Burger King; chip queries may include
Doritos and Lay's. A brand-only query can still resolve through an approved
alias to a canonical result, with a subtle matched-alias hint and generic
nutrition clearly treated as an estimate. Prefer explicit phrases such as
“Five Guys burger,” “McDonald's hamburger,” “Burger King Whopper,” “Doritos
tortilla chips,” or “Lay's potato chips” when an alias identifies a specific
food. A brand alone should not silently imply exact restaurant or package
nutrition.

Resolve a brand alias to a canonical food plus a verified configuration or
named variation when that mapping is supported. Keep brand identity in alias
metadata and show the canonical result name. Do not present the generic food's
nutrition as the restaurant or packaged product's exact nutrition without a
verified match; product-specific nutrition can be added as a separately
identified variation or source record.

Brand aliases should preserve meaningful food distinctions. For example,
Doritos points toward a tortilla-chip food and Lay's toward a potato-chip food;
if both are collapsed under a broad Chips canonical, retain the chip type as a
mutually exclusive choice or saved variation.

## Canonical grouping and option refinements

- **Burger:** Use one exclusive Protein selector for Beef (default), Chicken,
  or Bean. Each protein is a reusable component and selecting another replaces
  the prior patty; clearing the group allows a patty-free burger. Keep the old
  Bean burger ID hidden but available so existing history remains resolvable.
  Search aliases for patty and bean-burger terms resolve to the Burger canonical.
- **Biryani:** Add a mutually exclusive Protein choice for Chicken and Beef.
  The current generic USDA meat-biryani profile can overlap the added protein,
  so treat these combinations as draft until their base recipes are refined.
- **Biscuit:** Searches for Biscuits and gravy resolve to Biscuit, with Gravy
  as a reusable add-on. Preserve the combined food ID for history.
- **Coffee:** Coffee is the single canonical result; “black coffee” is an
  alias. Milk types are exclusive choices; sugar, cream, and syrup are
  add-ons.
- **Sandwich:** BLT is a named full-food variant under Sandwich. Keep the
  former BLT ID as a hidden component for history and saved configurations.
- **Fried fish:** Use the canonical display name Fried fish and map “breaded
  fried fish,” “fried fish fillet,” and “fish and chips” to it. Offer Fries as
  a separate optional companion; keep tartar sauce and ketchup configured on
  the fish.
- **Eggplant Parmesan:** Keep Pasta, cooked as a separate optional companion so
  its portion can be logged and edited independently.
- **Sandwich:** Fried chicken sandwich searches resolve to Sandwich, with
  fried chicken as a reusable exclusive filling. Preserve the former dedicated
  sandwich ID for diary history.
- **Yogurt and cereal types:** Flavored yogurt and frosted corn flakes remain
  nutrient-bearing type components under Yogurt and Cereal; brand/type aliases
  resolve to those generic canonical foods.
- **Generic brand aliases:** Goldfish cracker searches resolve to Crackers;
  retain the former branded ID for history and avoid presenting its label as
  generic brand-specific nutrition.
- **Pizza crust:** Keep regular and deep-dish crust IDs as internal Pizza
  customization components, not standalone search results. The malformed
  duplicate food_food_pizza_crust ID remains history-only; crust searches route
  to Pizza.
- **Taco:** Keep both Taco and Hard-shell taco as searchable foods, with the
  hard-shell entry offering mutually exclusive beef/chicken protein and
  cheddar, salsa, and lettuce as configured choices. Taco keeps its protein
  selector and the same common toppings. Offer refried beans and rice as
  optional companions for both Taco entries.
- **Hot dog:** Hot dog sausage remains an internal reusable component and its
  standalone search aliases resolve to Hot dog; preserve its identity for logs.
- **Cereal, Salad, and Hummus options:** Cereal offers mutually exclusive milk
  choices alongside cereal type. Salad and Greek salad each offer a dressing
  choice. Hummus suggests carrots, cucumber, celery, broccoli, snow peas, and
  snap peas as separate optional companions. Dressings and milks remain
  configured choices.
- **Breakfast casserole:** Include common contents choices for sausage, bacon,
  ham, cheese, and bell pepper. The generic USDA profile already contains meat
  and cheese, so ingredient-level totals need recipe-specific refinement.
- **Breakfast sandwich:** Keep the English muffin and one egg as removable
  included components. Offer sausage, bacon, or ham as exclusive meat choices
  and cheese as an optional addition.

- **Smoothie:** Use one searchable **Smoothie** canonical, with common fruit,
  liquid, yogurt, and nutrition-significant add-in choices. Preserve
  **Breakfast smoothie bowl** as history-only rather than a new search result.
- **Buffalo chicken dip:** Remove it from new search results because it is too
  specific; preserve the identity for existing diary history.
- **Popcorn:** Search returns **Popcorn**. Butter is an optional topping, not a
  separate canonical result. Route “butter popcorn” and “movie theater popcorn”
  searches to Popcorn; keep the former Butter popcorn ID history-only.
- **Soup model (open):** The catalog has 14 clear soup types: Chicken noodle,
  Tomato, Broccoli cheddar, Clam chowder, Minestrone, Vegetable, French onion,
  Lentil, Split pea, Miso, Chicken tortilla, Baked potato, Mushroom, and Ramen
  noodle soup. The Soups & stews category also contains
  Chicken chili, Vegetarian chili, Gumbo, and Jambalaya. Decide whether those
  14 soup types should become mutually exclusive variations under Soup, with
  add-ins in a separate options group, or remain distinct searchable foods.
  Preserve the distinct Chili, Gumbo, and Jambalaya identities during that
  discussion; their recipes and meal roles differ from a generic soup.

The taxonomy source and generated review workbook expose separate
comma-separated **Variations**, **Options**, and **Included components**
columns. Derive them from structured variant, suggested-addition, and
base-composition records during every preparation run so the summaries cannot
drift. In the inline enrichment readout, prioritize Variations and Options;
show calories, confidence, and evidence, and omit other macros unless requested
or needed to explain a material discrepancy.

## Data and history boundaries for implementation

- Give every Chase Food record a stable ID and a source identity that remains
  available when the source is disabled.
- Store aliases as searchable terms targeting a stable food ID.
- Store portions and component links as references to existing foods.
- Keep source toggles in lightweight user preferences.
- Filter search before ranking or presenting results, while retaining history
  reads by stable ID and saved nutrition snapshot.
- Do not remap an old Chase Food diary entry to a same-name USDA/OFF result.
- Changing a source toggle must not migrate, rewrite, or delete diary history.
- Nutrient/profile corrections should affect future logging; existing diary
  entries retain their logged nutrition snapshot.

## Review questions before implementation

1. What are the approved weights and visual cues for each size, especially
   pizza diameter plus slice count and burger cooked patty diameter?
2. Which restaurant and packaged-food aliases should be included first, and
   which can resolve to a verified variation or branded nutrition record?
3. Which source's nutrient profile will supply each Chase Food default, and how
   will draft estimates be distinguished from verified values?
4. For each proposed companion pairing, does it remain a separately editable
   food in the diary, with its own portion and nutrition, rather than a
   configured component of the parent?
5. Which portion and component amounts should be approved for the first
   release?

The companion PDF, [Chase Food customization concepts](chase-food-concepts.pdf),
shows the proposed source/search flow and one phone-screen concept per food.
It includes Cappuccino, Protein shake, Sandwich, Caesar salad, Salad, Potato salad, Lasagna, Chili, Beef stew, Chicken Parmesan, Chicken
piccata, Orange chicken, Roast turkey, Cheesecake, and Pancake. All nutrition
figures in that packet are illustrative placeholders, not values from the
workbook or verified nutrient data.


### Burger Protein selector

Burger uses one exclusive Protein group: Beef (default), Chicken, or Bean. Selecting another protein replaces the selected patty; clearing the choice logs the burger without a patty. The hamburger bun remains an included base component. Patty components stay internal and searchable aliases resolve to Burger. The Bean patty nutrition estimate uses locally bundled USDA FoodData Central record 2707473 (“Veggie burger patty, no bun”) as a medium-confidence analogue pending bean-specific refinement.


### 2026-10-19 item refinement decisions

- **Hummus with crackers:** Keep one assembled snack identity and expose
  Hummus (70 g) and Crackers (45 g) as included components. The 115 g serving
  estimate combines a USDA commercial-hummus serving with an FNDDS small or
  medium cracker bag; keep Low confidence because package ratios and cracker
  types vary.
- **Greek salad:** Use the USDA Greek Salad, no dressing profile. That source
  recipe already includes romaine, tomato, cucumber, olives, feta, anchovy, and
  other vegetables; the profile excludes dressing and stays Medium confidence.
- **Ground beef, cooked:** Use USDA cooked 85/15 beef crumbles as the reusable
  ingredient default, with Medium confidence because fat ratio and draining
  vary.
- The 2026-10-19 enrichment ledger corrects several unrelated baseline matches
  (including hot chocolate, cooked ground beef, and hard-shell taco) while
  preserving every food ID and existing diary history.

### 2026-10-21 configuration refinements

- **Cereal types:** Keep `food_cold_breakfast_cereal` as the single searchable
  canonical entry displayed as **Cereal**. Corn flakes, oat rings, granola,
  frosted flakes, bran flakes, shredded wheat, rice cereal, and muesli are
  exclusive nutrient-bearing cereal type variants. Their former IDs remain
  available for diary history and as variant components; cereal searches and
  type aliases resolve to Cereal. Milk choices stay exclusive and fruit/honey
  remain independent additions.
- **Naan:** Keep Plain naan as the default and Garlic naan as a mutually
  exclusive variation beneath Naan. The garlic variation uses a low-confidence
  draft composition based on naan, butter, and garlic; review its ingredient
  amounts before treating its calories as final.
- **Nachos:** Add chicken and cooked ground beef as optional toppings alongside
  the existing cheese, sauce, salsa, sour cream, and guacamole options.
- **Oatmeal:** Add raisins as an optional topping.
- **Omelet:** Expand multiple-select ingredients to include American cheese,
  mushrooms, bell pepper, onion, kielbasa, steak, spinach, tomato, and
  mozzarella, retaining the existing cheddar, ham, and bacon choices. Kielbasa
  uses the USDA grilled fully cooked record as a medium-confidence reusable
  ingredient.
- **Panini:** Offer a mutually exclusive filling choice (ham, turkey, roast
  beef, or chicken) and a mutually exclusive cheese choice (cheddar, American,
  provolone, Swiss, mozzarella, or Pepper Jack). These are customizable
  ingredients under Panini, not separate diary companion suggestions.
