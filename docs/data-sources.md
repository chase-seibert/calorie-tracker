# Food data sources

See [Catalog pruning and size options](catalog-sizing.md) for the exact current
filters, measured row costs, and larger catalog projections.

See [Foods to add or investigate](missing-foods.md) for the running list of
personal coverage gaps and their current match counts.

## Chase Food

Chase Food is a curated local catalog of canonical foods, search aliases,
natural portions, and reusable components. It is available in Settings as a
local food data source and is off by default.
The design direction and source/history rules are recorded in
[Chase Food taxonomy and source](chase-food-taxonomy.md), with 25 phone-screen
concepts in [Chase Food customization concepts](chase-food-concepts.pdf).

Settings → Food & Meals → Food Data Sources lets each local catalog (USDA,
Open Food Facts, and Chase Food) be included in or excluded
from search independently. A disabled source contributes no new search results;
its records remain available to resolve existing diary history and retain the
nutrition snapshot used when logged. The planned Chase Food search uses
canonical names and aliases, omitting category and food-kind labels from
results.

The linked review workbook tracks the 508 food identities, their nutrient
confidence, portion estimates, aliases, and configurable component options.
Nutrition values are screening estimates from the existing catalog. The
calorie and macro figures in the concept PDF are placeholders.

Processed-meat and red-meat classifications are maintained as independent
flags in a reviewed, stable-ID source at
[`data/food-catalog/meat-classifications.json`](../data/food-catalog/meat-classifications.json).
It records Chase Food's positive tags and reviewed source-specific corrections
for USDA and Open Food Facts. The catalog build carries them into the existing
SQLite classification columns. A cured or otherwise preserved mammalian meat
can have both flags set; processed poultry can have only the processed-meat
flag. Only ingredients in a Chase Food item's default composition affect its
tags; optional customization choices do not change the base food's
classification.

## USDA FoodData Central

The current catalog imports Foundation Foods, SR Legacy, and FNDDS. USDA Branded
Food is documented as a larger future preset rather than included today.
FoodData Central data are public-domain U.S. government data. The app retains
FDC IDs and source labels for traceability.

Current downloads: <https://fdc.nal.usda.gov/download-datasets/>

## Open Food Facts

Open Food Facts is most useful for packaged products and barcode lookup. Records
retain the OFF barcode/source ID. The database is offered under the Open Database
License (ODbL); individual database contents use the Database Contents License.
The app displays attribution and keeps the derived OFF subset distinguishable.

Project and reuse terms: <https://world.openfoodfacts.org/terms-of-use>

## Snapshot strategy

Raw upstream exports are not appropriate app assets: USDA's complete release is
multiple gigabytes expanded and the current OFF Parquet export is several
gigabytes. The pipeline emits a purpose-built SQLite snapshot containing only the
fields this app uses. USDA provides generic-food depth; OFF is ranked toward
popular U.S.-tagged packaged products with calorie data. Snapshot size and OFF row limit are
build-time controls. The initial bake-off snapshot requests 1,000 OFF products
to stay within the public search service's documented anti-abuse limits.

The checked-in snapshot currently contains 13,545 USDA foods and 935 popular,
U.S.-tagged Open Food Facts products with calorie data in a roughly 4.7 MB SQLite
file. It now retains every usable source portion rather than pruning each food
to one serving. Dietary Fiber is available for 12,820 USDA rows and 789 Open
Food Facts rows (13,609 of 14,480 foods, or 94.0% overall); missing Fiber remains
nullable rather than being compiled as zero.

## Coverage expansion options

1. Keep the current generic USDA depth and rely on custom foods, saved meals,
   and curated packaged-food supplements for gaps. This has the best size and
   search-quality tradeoff.
2. Run `make catalog-refresh OFF_PAGES=50` (or another page count) to include
   more popular U.S. packaged products. At the current measured row cost, every
   additional 1,000 retained records adds well under 1 MB, but public API search downloads are
   deliberately rate-limited.
3. Build from full exports. USDA Branded Food and the full Open Food Facts export
   provide far broader packaged-food coverage, but their raw inputs are hundreds
   of megabytes to several gigabytes. They should be filtered offline to U.S.
   products with complete calorie/macro data before generating the app asset.

Popularity expansion alone does not guarantee personally relevant coverage.
For example, psyllium is absent from the compact catalog and its generic USDA
inputs. It is abundant in USDA Branded and broader Open Food Facts, but the U.S.
OFF matches have low scan counts: top 5,000 does not include them, and top
25,000 inclusion is tie-dependent. Prefer a small curated supplement or a
filtered USDA Branded slice for known personal gaps. See the measured probe in
[Catalog pruning and size options](catalog-sizing.md#coverage-probe-psyllium).

Neither bundled source subset currently has a canonical generic café Americano
record. Custom foods and saved meals are the preferred way to represent personal
preparations that are absent from the upstream snapshot.

## Grouped catalog experiment

Run `make catalog-grouped-report` to build a non-production catalog experiment
under `data/work/`. The generated database preserves every source row, maps each
row to a canonical food group, and exposes one representative search row per
group. Its HTML report summarizes consolidation, representative selection, and
preparation families whose nutrition ranges require review.

The grouping is intentionally heuristic. Alternate preparations remain indexed
as aliases, but a canonical record's nutrients must not be treated as equivalent
to every member preparation without a product decision and data-quality review.

Run `make catalog-family-report` for the more structured entity-resolution
experiment. It produces a separate database with three levels: canonical food
families, nutrition-bearing preparation variants, and original source records.
It includes both a family-level search index and a variant-level search index so
generic queries can return fewer rows while explicit preparation queries retain
the correct nutrition.
