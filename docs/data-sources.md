# Food data sources

See [Catalog pruning and size options](catalog-sizing.md) for the exact current
filters, measured row costs, and larger catalog projections.

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
U.S.-tagged Open Food Facts products with calorie data in a roughly 4.6 MB SQLite
file. It now retains every usable source portion rather than pruning each food
to one serving.

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

Neither bundled source subset currently has a canonical generic café Americano
record. Custom foods and saved meals are the preferred way to represent personal
preparations that are absent from the upstream snapshot.

## MyFitnessPal

MyFitnessPal history is user-owned personal data and is never bundled. It is
imported on-device and remains in the writable personal store. The importer will
be finalized against the user's actual export.
