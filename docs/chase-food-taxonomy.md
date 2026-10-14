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
provides the rationale and initial model. The current review dataset has 521
catalog identities (506 search-enabled), 1,908 portion mappings, 1,217 alias
records, 321 configurable component options, and 28 presets. Portion and option
amounts are first-pass estimates; nutrition values are matched from the bundled
USDA/Open Food Facts catalog and still need review when confidence or
preparation notes flag them. The 2026-10-14 local enrichment revision adds source-level nutrition and
composition evidence for 20 previously lowest-confidence searchable foods;
the generated review workbook is rebuilt from the same catalog projection.

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
   Cheese, bacon, and fries are reusable foods/components, not duplicate burger
   nutrition records. Presets such as “Bacon cheeseburger” can be convenient
   selections built from those existing identities.
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
8. **Reserve quick controls for meaningful nutrition changes.** Show an add-on
   as a quick choice when a usual serving materially changes calories or one of
   the tracked macros. For a burger, cheese, bacon, mayonnaise, ketchup, and
   fries qualify; lettuce, tomato, onion, pickle, and a small mustard serving
   do not. Keep unlisted ingredients available through Add ingredient when
   useful. Apply this judgment to the modeled amount rather than a fixed
   calorie cutoff.
9. **Keep brand searches generic and label evidence separate.** Map cereal
   brands to the closest generic food or to Cereal when the current types do
   not fit. Store manufacturer label values as research evidence with product,
   serving size, date, and source; do not use them as generic nutrition values
   or imply that an alias has brand-specific nutrition.
   The initial cereal comparison is checked in at
   `data/chase-food/cereal-brand-research.json` and appears as the **Cereal
   Brand Research** tab in the review workbook.

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
- Show optional ingredients and related foods in **Add to this food or meal**.
  Keep food identity distinct: selecting fries from Burger's screen adds a
  separate reusable food alongside the burger.
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

## Size and food-specific directions

- **Burger:** Include a bun by default. Offer one exclusive protein choice—beef,
  chicken, or bean—with beef selected by default; users can clear the selection
  for a patty-free burger. Offer cheese, bacon, mayonnaise, ketchup, and related
  sides such as fries. Keep garnish
  ingredients out of quick controls; they remain searchable through Add
  ingredient. Use a visual size cue as well
  as weight: draft cues could be a small slider/hockey-puck-scale patty, a
  standard roughly 4-inch patty, and a larger roughly 5-inch patty. Review
  diameter and cooked weight before assigning nutrition.
- **Pizza:** A serving is one slice. Size choices describe the pizza's diameter
  (for example, a slice from a 12-, 14-, or 18-inch pizza), with the number of
  cuts stated because diameter alone does not define slice area. A proposed
  first quick set is pepperoni, sausage, mushrooms, extra cheese, onion, and
  green pepper; consider olives, bacon, ham, chicken, pineapple, and jalapeños
  as searchable additions. This is a review list, not a measured popularity
  ranking.
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
| Taco Night; Red Chile Chicken Enchiladas; Bean and Cheese Tomatillo Enchiladas | **Taco** for taco night, with one exclusive protein choice, meaningful toppings, and refried beans and rice as related foods. Keep low-impact toppings out of quick controls. Enchiladas can share an **Enchiladas** entry with a filling choice if users log them often. |
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
  fried fish,” “fried fish fillet,” and “fish and chips” to it.
- **Breakfast casserole:** Include common contents choices for sausage, bacon,
  ham, cheese, and bell pepper. The generic USDA profile already contains meat
  and cheese, so ingredient-level totals need recipe-specific refinement.
- **Breakfast sandwich:** Keep the English muffin and one egg as removable
  included components. Offer sausage, bacon, or ham as exclusive meat choices
  and cheese as an optional addition.

Both the taxonomy source and the generated review workbook expose an **Options
(add-ons and variants)** food-table column. Generate it from structured
included-composition and addition records on every catalog preparation run so
the summary cannot drift from selectable options.

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
4. When a configuration includes a related food such as fries, should one
   action create two diary entries or one meal-style entry with component
   snapshots?
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
