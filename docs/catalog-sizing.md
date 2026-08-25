# Catalog pruning and size options

## Purpose

The bundled catalog should make ordinary logging feel complete while keeping
search instant, installation small, and catalog refreshes reproducible. This
document separates measured results from projections so decisions about broader
packaged-food coverage are explicit.

## Current compact catalog

The checked-in SQLite file is generated from cached upstream snapshots by
`scripts/build_food_catalog.py`.

| Input | Candidate rows | Rows retained | Why rows are removed |
| --- | ---: | ---: | --- |
| USDA Foundation, April 2026 | 395 | 321 | Missing a usable name, ID, or calorie value |
| USDA SR Legacy, April 2018 | 7,793 | 7,793 | None in this snapshot |
| USDA FNDDS, October 2024 | 5,432 | 5,431 | Missing a usable name, ID, or calorie value |
| Open Food Facts, top 1,000 U.S.-tagged products | 1,000 | 935 | Missing a product name, barcode, or calorie value |
| **Total** | **14,620** | **14,480** | **140 rejected** |

The resulting file is approximately 4.7 MiB: 13,545 USDA foods and 935 Open
Food Facts products. The combined catalog currently averages about 337 bytes
per retained row, including indexes and the two meat-presence flags.

## What is pruned

### Entire datasets

- USDA Branded Food is not bundled. The generic-focused Foundation, SR Legacy,
  and FNDDS datasets are included in full subject to the validation rules above.
- Open Food Facts is capped before normalization. The API request asks for
  U.S.-tagged products ordered by scan popularity, so the catalog favors common
  packaged products rather than attempting full coverage.
- Custom foods and saved meals are personal data. They remain in the writable
  on-device store and are never compiled into the shared SQLite asset.

### Fields

Each retained catalog row keeps only:

- source and source ID;
- name, brand, and barcode;
- calories, carbohydrates, fat, and protein per 100 g;
- usable portion labels and their gram weights;
- compiled processed-meat and unprocessed-red-meat presence flags;
- a source popularity/ranking value.

Source categories, recipe ingredients, and ingredient tags contribute to the
meat flags during compilation and are then discarded. Micronutrients, allergens,
images, packaging, category trees, marketing text, and source audit history are
also discarded. SQLite adds a compact
FTS5 index over name and brand plus indexes for source ranking and barcodes.

### Normalization rules

- A record must have a usable ID, name, and calorie value.
- Negative or non-finite nutrition values are rejected or clamped to zero.
- Missing individual carbohydrate, fat, or protein values currently become
  zero. This is a known quality tradeoff; a stricter build could reject such
  records instead.
- Every USDA portion with a positive gram weight is retained. Duplicate
  label/weight pairs are collapsed within a food.
- Open Food Facts serving weights are retained when the source provides either
  `serving_quantity` or a parseable gram value in `serving_size`.
- Duplicate source IDs replace earlier copies during insertion.

## Size presets

These projections use the measured 335-byte average as a starting point and add
headroom for longer branded names, brands, barcodes, and portions. Actual sizes
must be measured after building because FTS compression and data completeness
are not perfectly linear.

| Preset | Approximate retained items | Estimated app asset | Coverage and tradeoff |
| --- | ---: | ---: | --- |
| Current compact | 14,480 | 4.7 MiB measured | Strong generic foods; only the most popular packaged products |
| OFF top 5,000 | 18,000–18,500 total | 6–8 MiB | Modest packaged-food improvement with almost no install concern |
| OFF top 25,000 | 36,000–38,000 total | 12–20 MiB | Good personal-app balance; refresh through the rate-limited search API is slow |
| USDA Branded | 350,000–450,000 total after validation | 120–220 MiB | Much broader U.S. packaged coverage and UPC lookup; more duplicates and stale products |
| Large filtered OFF export | 200,000–1,000,000 total | 70–400 MiB | Broad crowd-sourced barcode coverage; variable completeness and substantially heavier builds |
| Near-full combined export | More than 1 million | 350 MiB–1+ GiB | Maximum offline coverage, but poor fit for a lightweight personal install |

The USDA API reported 433,082 current Branded records on August 3, 2026. USDA's
April 2026 Branded archives are 195 MiB zipped / 3.1 GiB expanded for JSON and
428 MiB zipped / 2.9 GiB expanded for CSV. Those raw sizes are much larger than
the projected app asset because this project keeps only a small field subset.
See the official [FoodData Central downloads](https://fdc.nal.usda.gov/download-datasets/)
and [Branded Food documentation](https://fdc.nal.usda.gov/GBFPD_Documentation/).

Open Food Facts exposes millions of global products and supports field-limited,
paginated search requests. Its documentation asks clients to request only the
needed fields; this pipeline follows that guidance. See the official
[search documentation](https://openfoodfacts.github.io/documentation/docs/Product-Opener/v2/search/get-search/)
and [bulk-export guidance](https://openfoodfacts.github.io/search-a-licious/users/tutorial/).

## Coverage probe: psyllium

Psyllium is a useful example of why total row count and personal coverage are
different goals. A probe on August 4, 2026 found:

- no `psyllium` match in the checked-in catalog or its downloaded USDA
  Foundation, SR Legacy, and FNDDS inputs;
- 780 USDA Branded search matches, including dedicated NOW psyllium powder and
  whole-husk products with tablespoon household servings;
- 271 full-text Open Food Facts matches globally, 77 of them U.S.-tagged;
- the best U.S. Open Food Facts psyllium matches had only one recorded scan,
  while the product at the 5,000-item popularity cutoff had three scans.

Consequently, OFF top 5,000 does not cover psyllium. OFF top 25,000 may select
some one-scan products, but inclusion is not reliable because many products tie
at that rank and the pipeline has no secondary tie-breaker aimed at personal
relevance. The full or a large filtered OFF export covers it, while USDA Branded
is the strongest source for recognizable U.S. psyllium products and useful
household portions.

Sources: [FoodData Central API](https://api.nal.usda.gov/fdc/v1/foods/search?api_key=DEMO_KEY&query=psyllium&pageSize=20&dataType=Branded),
[Open Food Facts Search-a-licious](https://search.openfoodfacts.org/search?q=psyllium&page_size=20),
and the local SQLite/source-snapshot inspection recorded in this repository.

## Recommended next preset

For broad packaged-food coverage, the top 25,000 U.S.-tagged Open Food Facts
products remain a useful future bulk-export projection while keeping the
complete generic USDA subset. The current concrete offline debug preset is the
Search-a-licious top 10,000 U.S.-filtered snapshot, because the legacy paginated
API does not currently provide a reliable unauthenticated path to 25,000 rows.
The 10,000-row preset materially improves barcode coverage but should not be
treated as sufficient for known low-popularity personal foods. The targeted
gap catalog and a small USDA Branded supplement remain better options for gaps
such as psyllium.

Small refreshes can use the existing API workflow:

```sh
make catalog-refresh OFF_PAGES=50
```

That requests 5,000 candidates. The public search API is limited to ten search
requests per minute, so 25,000 candidates would take at least about 25 minutes.
For larger presets, the builder should gain a streaming bulk-export input rather
than making hundreds or thousands of search requests.

## How to evaluate a new snapshot

Every catalog-size experiment should record:

1. candidate and retained counts by source;
2. final SQLite size after `ANALYZE` and `VACUUM`;
3. exact-query success for a personal test list, initially including Americano
   and psyllium as known coverage gaps;
4. median and worst-case on-device search latency;
5. the percentage of OFF/Branded rows with all four tracked macros;
6. duplicate-looking results for common terms such as egg, butter, milk, and
   cheddar.

The goal is not the largest possible row count. It is the smallest snapshot that
reliably contains the foods actually logged while preserving fast, useful search
ranking.
