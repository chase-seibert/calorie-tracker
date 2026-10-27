# Chase Food data model plan

**Status:** Approved and implemented for the initial Chase Food catalog,
source toggles, configurable logging, saved variations, and food feedback.

**Visual reference:** [Chase Food customization concepts](chase-food-concepts.pdf)
and the [Bagel customization concept](chase-food-bagel-concept.pdf) are saved
alongside the project documentation. They show the source settings,
canonical search, customization screens, and example foods. Its nutrition
figures are mock values and must not be imported as catalog data.

## User requirements

- Add **Chase Food** as a distinct local food data source in Settings. Let the
  user enable or disable each local source independently. The intended test
  setup is Chase Food on, USDA off, and Open Food Facts off.
- Search canonical Chase Food identities. Synonyms, cookbook names, and
  approved restaurant or product aliases should find the canonical item without
  creating duplicate results. Search results omit taxonomy category and food
  kind.
- Turning off a source filters it from new catalog search results. It must not
  delete the source, break saved configurations, or unlink diary history.
- A canonical food has a quick-add default and a customization model for
  portions, exclusive choices, included ingredients that can be removed,
  optional ingredients, companion recommendations, and ingredients selected
  through search.
- Logging a customized food saves the selected configuration for reuse under
  its canonical result. A diary entry retains the selected configuration and
  nutrition snapshot so a later catalog update cannot rewrite history.
- Import the taxonomy and alias data as versioned project data. Use the cookbook
  mapping and the review PDF as editorial/design references, not as nutrition
  sources.

## Architecture and data model

### Existing app boundary

The app already has a read-only bundled `FoodCatalog.sqlite3`, queried by
`CatalogStore`, and a writable App Group `Diary.sqlite`, managed by
`DiaryRepository`. `Food` identity is the pair `(FoodSource, sourceID)`; diary
entries embed a `Food` snapshot and nutrient totals. The catalog builder creates
the `foods` table and FTS5 index. Current `FoodSource` values are USDA, Open
Food Facts, and custom foods. The Settings source screen currently shows
catalog counts but does not persist source toggles.

Keep Chase Food in the bundled catalog so one catalog reader and one search
index can serve all sources. Put aliases, composition templates, and profile
provenance in additional tables in that same immutable database. Keep user
source preferences and saved food configurations in the writable diary store.
Do not make the app fetch the workbook or cookbook at runtime.

### Catalog records

| Record | Proposed fields and purpose |
| --- | --- |
| `FoodSource.chaseFood` | New stable enum value, displayed as **Chase Food**. Do not reuse `.custom`, which identifies user-created foods. |
| `foods` row | Existing app-compatible search/log projection: stable `source_id`, source, canonical display name, serving/portion data, default nutrient total, meat flags, and a search-enabled flag. Chase Food rows use `source = chaseFood`. Retired individual deli-sandwich identities remain resolvable for history but no longer appear in search. |
| `chase_food_metadata` | One row per Chase Food identity with category, food kind, confidence, review reasons, and matched source provenance. |
| `chase_food_aliases` | Stable target food ID, alias text, and alias kind (`canonical`, `synonym`, or `brand`). FTS indexes canonical names and approved aliases; results deduplicate by target ID. |
| `chase_food_options` | Parent/option/component IDs, component label and grams, relationship, default-selected flag, order, optional group name, and selection mode (`exclusive` or `multiple`). Component references point to reusable catalog foods. |
| `chase_food_companions` | Parent and companion food IDs, display label, and order. Chase Food parents use their stable source ID; parents in another catalog use a source-qualified ID such as `usda:2705864`. These are opt-in recommendations between independent foods; resolve both foods through the catalog rather than duplicating nutrition or modeling the companion as a parent option. |
| Food table choice summaries | Separate comma-separated `Variations`, `Options`, and `Included components` columns derived from structured variant and base-composition rows. Companion recommendations remain separate and do not contribute to the parent summaries. Regenerate summaries during every catalog preparation and in the nutrition review workbook. |
| `metadata` | Dataset revision and identity count, alongside the existing catalog metadata. |

`foods` remains the compatibility surface used by existing search, logging,
portion, and diary code. The options table defines removable included foods,
single-choice groups, multi-choice groups, configured additions, and food
variants. Each option points to a reusable nutrient-bearing `Food` record and
an amount; do not store ad hoc calorie deltas for modifiers. The separate
companions table recommends independently recognizable foods to log alongside
a parent. A companion does not change the parent configuration or nutrition.
The builder stores
the matched profile as the canonical default. Additions adjust that total by
the difference from their default-selected state. A `variant` option replaces
the canonical profile at the selected portion weight, then appears as a logged
component when it is not the canonical base itself.

`amount_grams` on an included component or addition is the component mass for
one defined parent serving. It is not the component food's default serving
size. Convert the logged parent quantity to parent-serving equivalents, then
scale the option nutrients by that factor. This keeps toppings proportional
when a parent is logged as multiple slices, ounces, grams, cups, or other
supported units. The selected parent portion supplies the conversion basis; if
distinct parent sizes have different recipes or topping coverage, store
size-specific component amounts or a documented size-scaling rule. For named
parent sizes whose component records do not carry size-specific amounts, treat
the Medium portion as the component reference; if there is no Medium, use a
Default portion, then the first portion. Scale every option amount by the
selected parent grams divided by those reference grams. Foods with only one
parent portion retain their authored component amounts. Use this same resolved
amount in option calorie labels, configured totals, and saved component
snapshots. Do not scale companion foods with the parent: each companion retains
its own amount and diary entry.

The stable catalog identity is `chaseFood:<sourceID>` (for example,
`chaseFood:food_burger`). Add Chase Food to `FoodCatalogIdentity` wherever
catalog identities must be resolved or customized. Preserve current USDA and
Open Food Facts raw IDs so existing diary snapshots continue decoding.

### User preferences and source filters

Store each source's enabled state as a small user preference, separate from
diary content. USDA and Open Food Facts stay enabled by default, preserving the
existing search setup; Chase Food is opt-in. Settings can change them
independently, allowing Chase-only testing. Personal foods and saved meals
remain in the personal library, outside local-catalog source toggles.

Apply enabled-source filtering in `CatalogStore.searchAll` before results reach
`DiaryEngine.searchItems` and its canonical-first ranking. Keep alias matching
inside the source's search index, return the canonical food once, and retain
the matched alias only as optional result context. Preserve the current broad
query behavior that gives canonical catalog foods priority over matching
personal meals. Keep source filtering out of history reads: diary rows resolve
from their saved identity and snapshots even when that catalog is disabled.

Built-in configuration options should resolve from the bundled catalog by
stable IDs even when their source is disabled for discovery. The Add ingredient
search uses the sources currently enabled for discovery; once selected, the
component is retained in the configuration and diary snapshots.

### Saved configurations and diary snapshots

Add a separate `SavedFoodConfiguration` model rather than representing every
variation as a custom food or saved meal. A saved variation is a personal
configuration of one canonical source item.

```text
SavedFoodConfiguration
  id: UUID
  baseFood: FoodCatalogIdentity
  name: String?                    // optional user label; otherwise derive a short summary
  portionID: String?
  selectedOptions: [OptionSelection]
  removedDefaultOptionIDs: [String]
  addedFoods: [ConfiguredFoodReference]
  createdAt: Date
  updatedAt: Date
  lastUsedAt: Date?

OptionSelection
  groupID: String
  optionID: String

ConfiguredFoodReference
  foodIdentity: FoodCatalogIdentity? // present when the catalog record has an identity
  foodSnapshot: Food                  // fallback and custom/imported ingredients
  amount: Double
  unit: LogUnit
  portionID: String?
  role: included | addition | relatedFood
```

Persist these in `DiaryDocument` for transfer/backup compatibility and in an
indexed `saved_food_configurations` table keyed by UUID with a `base_food_id`
column for grouping configurations under their canonical result. Serialize the
selection payload in the same way the diary repository currently stores
personal foods and meals. Keep saved variations separate from `customFoods`
and `SavedMeal`; they have different identity and search behavior.

Add an optional `FoodConfigurationSnapshot` to `DiaryEntry`. It records the
canonical base identity, selected option IDs, portion choice, resolved
component `Food` snapshots and amounts, and the catalog revision used at log
time. `DiaryEntry.food` continues to identify the canonical Chase Food item;
`DiaryEntry.nutrients` stores the computed total. This keeps history resolvable
when Chase Food is disabled or a future catalog changes. Existing entries omit
the new optional field and remain valid.

On a future log from a saved configuration, resolve its stable option and food
IDs against the current catalog so corrected nutrient profiles affect new
logs. Persist the resolved values in the new diary snapshot. If an option is
retired, use the saved component snapshot and flag the configuration for
review rather than silently dropping it.

### Nutrition quality and initial data

The source workbook now contains 521 catalog identities, 1,908 portions, 1,217
alias records, 321 configurable component options, and 28 presets. Its nutrition values are screening estimates matched to the
existing catalog; they are not recipe analyses or product-label values. The
first pass matches each identity to the existing bundled USDA/Open Food Facts catalog and scales the selected
record to the workbook's default grams. Every match records its source ID,
matched name, match basis, similarity, and review reasons. Only exact canonical
name matches receive High confidence. Approximate matches are flagged for
review; no PDF mock values are used. The review spreadsheet is generated from
the same `data/chase-food/catalog.json` manifest consumed by the catalog
builder.

The data build should consume checked-in, reviewable source files under a
dedicated `data/chase-food/` directory and produce the Chase Food rows and
metadata as part of `FoodCatalog.sqlite3`. Keep source IDs stable across builds.
Expose searchable canonical identities while keeping legacy history records and
nutrient-bearing option components available by stable ID but out of search.
Keep category and food-kind metadata in the data if useful for curation, but do
not include them in result rows.

### Storage migration

Saved configurations, food suggestions, and optional entry snapshots are
persisted in `DiaryDocument` and indexed in additive SQLite v2 tables. The
migration creates tables and indexes transactionally without rewriting diary
rows. Missing JSON collections and snapshots decode as empty or nil. Document
schema version is 10, and the supported JSON-version range includes it. Keep
existing diary rows, IDs, quantities, nutrient snapshots, and WAL-safe backup
behavior intact.

## Validation coverage

The implementation is validated with catalog-build checks, app tests, and
simulator screens for the 25 foods in the concept PDF. Nutrition estimates and
portion mappings remain review data; the PDF's illustrative values are not
used as nutrient sources.

1. Exact canonical name, synonym, cookbook alias, and brand alias searches all
   return one Chase Food result with the canonical display name. Category and
   food-kind metadata do not appear in the result.
2. A one-word query ranks a canonical Chase Food result ahead of matching
   complex personal meals. A specific multiword query still matches the
   intended preparation.
3. Each source toggle filters only that source from new catalog results. The
   Chase-only test setup returns no USDA or Open Food Facts search results.
4. Turning a source off leaves a previously logged item, its macros, date,
   favorite/history references, and configuration snapshot readable.
5. The builder computes default canonical nutrients from selected default
   components. Removing a default item subtracts that component; adding one
   component adds its nutrients; mutually exclusive groups cannot select two
   values or zero values when a choice is required.
6. Add ingredient can select an enabled catalog item, and a saved configuration
   can add that item again after search is closed.
7. Saving and reusing a configuration keeps it grouped under its base food.
   Updating or deleting the reusable variation does not mutate prior diary
   entries.
8. A catalog nutrient correction affects a new log created from a saved
   configuration while the earlier diary snapshot remains unchanged.
9. A missing/retired catalog option falls back to its saved snapshot and is
   surfaced for review; no component is silently lost.
10. Existing JSON diary versions and SQLite v1 databases migrate with empty
    configuration collections and preserve existing records. SQLite v2 opens
    after the additive migration and continues normal transactional writes.
11. Unavailable profiles never display as zero-calorie foods; estimated values
    retain their quality state and attribution.

## Approved implementation decisions

- Expose searchable canonical identities in Chase Food. Keep history-only and
  internal option-component records resolvable by stable ID. Confidence and
  review reasons are tracked per identity in the synchronized review spreadsheet.
- Keep USDA and Open Food Facts enabled and Chase Food disabled by default;
  disabling a source only filters new catalog discovery and leaves diary
  snapshots intact.
- Keep configured additions and components in the primary diary entry with its
  configuration snapshot. Store companion recommendations as separate
  parent-to-food relationships; selecting one creates its own ordinary diary
  entry with its own portion and nutrition. Logging a parent and selected
  companions together is one atomic day-scoped write, while each entry remains
  independently editable.
- Map restaurant and product aliases to generic canonical identities without
  making brand-specific nutrition claims. Keep manufacturer label comparisons
  in separate research evidence with the product, serving size, access date,
  and source; never treat a brand alias as proof of generic nutrition.
- Persist free-text food suggestions in the SQLite diary and queue them in the
  existing signed analytics upload pipeline.
- Group saved Chase Food configurations beneath their canonical search result.
- Match the customization control groups from the concept PDF, including
  exclusive choices (such as bread, filling, milk, or cereal type), multiple
  configured additions (such as sandwich spreads), removable base ingredients,
  and portion sizes. Curate relevant side dishes as separate optional companion
  recommendations, not as configured components. Keep internal style choices
  out of diary constituent foods.
- Use one searchable `Bagel` identity. Cream cheese is an optional spread, and
  bagel types are mutually exclusive nutrient-bearing variants; selecting a
  type replaces the base profile at the chosen portion size. Keep the former
  `food_bagel_with_cream_cheese` identity history-only and route its search
  aliases to `food_bagel`.
