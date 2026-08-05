# Foods to add or investigate

This is a running list of foods that were not found in the current bundled
catalog but may be useful for personal logging. Add new items here as they
come up, and keep the query spelling and dataset counts together so catalog
coverage decisions are based on actual gaps.

## Current snapshot

Checked August 4, 2026 against the checked-in
`CalorieTracker/Resources/FoodCatalog.sqlite3`:

- USDA: 13,545 entries from Foundation Foods, SR Legacy, and FNDDS.
- Open Food Facts: 935 popular, U.S.-tagged packaged products.
- A “match” below uses the app’s current search behavior: all words must be
  present in the name or brand, with prefix matching for each word. Counts are
  food entries, not serving-size rows.

| Food or search | USDA matches | Open Food Facts matches | Likely source for a fuller match | Notes |
| --- | ---: | ---: | --- | --- |
| Psyllium | 0 | 0 | USDA Branded Food; broader Open Food Facts; MyFitnessPal history | The spelling is **psyllium**. A prior probe found 780 USDA Branded matches and 271 full-text Open Food Facts matches globally, including 77 U.S.-tagged matches. |
| Americano | 0 | 0 | MyFitnessPal history or a custom food for a café preparation; USDA Branded/Open Food Facts for packaged products | No canonical generic café Americano is present in either bundled subset. |
| Buttermilk bread | 0 | 0 | USDA Branded Food; Open Food Facts; MyFitnessPal history | The catalog has related buttermilk entries, but none also contain bread. |
| Oroweat buttermilk bread | 0 | 0 | USDA Branded Food; Open Food Facts barcode/product records; MyFitnessPal history | Brand spelling: **Oroweat** (often said as “Oro Wheat”). Confirm the exact variety from the package or prior history when available. |
| Mint tea | 0 | 0 | USDA generic foods or USDA Branded Food; Open Food Facts for packaged tea; MyFitnessPal history | The catalog has mint and tea entries separately, but no entry matching both terms. |

### Related results that are not substitutes

These counts help explain why a search can feel close without providing the
desired food:

| Broad query | USDA | Open Food Facts |
| --- | ---: | ---: |
| Buttermilk | 30 | 2 |
| Mint | 4 | 1 |
| Tea | 92 | 1 |

The related rows may describe a different food, preparation, or product and
should not be treated as coverage for the requested item.

## Dataset notes

- **USDA FoodData Central generic subset:** Foundation Foods, SR Legacy, and
  FNDDS are bundled today. This is strongest for generic ingredients and
  preparations. USDA Branded Food is not bundled and is the most promising
  USDA source for recognizable packaged items such as Oroweat bread and
  psyllium products.
- **Open Food Facts:** The bundled slice is intentionally limited to popular,
  U.S.-tagged products. A broader export or a larger popularity slice may find
  packaged bread, tea, and psyllium products, but low-scan products are not
  guaranteed to appear.
- **MyFitnessPal:** Imported history is personal on-device data, not part of
  the shared catalog. It is the best place to look for an item logged before,
  especially a specific café drink or branded bread.
- **Custom food:** A custom entry is the fallback for a preparation that is
  absent from upstream datasets, such as a café Americano with a known serving
  size.

## Adding another item

Record:

1. The name used in the search and any brand or product spelling.
2. The current USDA and Open Food Facts match counts.
3. The broader dataset most likely to contain it.
4. Any related results that are easy to mistake for the requested food.
5. The date of the catalog snapshot used for the count.

When the catalog changes, rerun the checks for this list. A zero in the local
catalog means “not bundled,” not “the food does not exist in any upstream
dataset.”

## Offline debug catalog variants

Concrete larger Open Food Facts debug catalogs can be built without changing
the app asset:

```sh
make catalog-debug
```

This creates ignored SQLite files under `data/work/catalogs/`:

- `catalog-off-search-top-10000.sqlite3`: the complete current generic USDA
  subset plus the largest practical U.S. Open Food Facts popularity snapshot
  available through the Search-a-licious API (up to 10,000 results).
- `catalog-gap-search.sqlite3`: the generic USDA subset plus up to 100 targeted
  Open Food Facts results for each missing-food topic.

The report includes match counts and top-five results for every item in this document at
`data/work/catalog-reports/missing-foods.md`.

The older Open Food Facts endpoint used by the app’s refresh command currently
limits unauthenticated pagination, so it is not used to label a 25,000-product
variant. The debug catalogs record concrete retrieved sizes rather than
claiming coverage that was not downloaded.

These databases are offline debugging artifacts only. The Xcode project still
references only `CalorieTracker/Resources/FoodCatalog.sqlite3`, so the larger
variants are not copied into or shipped with the app.
