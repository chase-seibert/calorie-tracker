# Food classification resolution

## SQLite-adjusted implementation plan

1. Preserve omitted meat flags as unknown, independently for processed and red
   meat. Record import, user, catalog, or name-rule provenance without changing
   the food's identity, nutrition, portions, or weight.
2. Resolve incoming foods in the shared domain engine, using known catalog IDs
   or barcodes, then conservative ingredient-name/alias matches, then name rules.
   Distinguish an exact catalog identity from agreement on classification across
   several preparation variants. Do not pick the first text-search result.
3. Show Automatic/Yes/No choices and conflicting suggestions in import and manual
   food editors. Keep explicit supplied values until the user changes them.
   Derived meal flags remain separate from explicit meal overrides.
4. Commit import/library/diary changes through `DiaryRepository` in one transaction.
   Keep historical reclassification separate from storage conversion. Provide an
   explicit review with a verified WAL-aware backup before correction.
5. Test resolution, indexed-column parity, snapshots, rollback, stale review,
   relaunch and quick logging; audit the known catalog false negatives.

These steps are implemented. No device deployment or owner-history repair is
part of this local change.

## Persistence and writer boundaries

`Food.meatResolution` is an optional value inside existing per-row food payloads:
it contains independent flag sources, the input name, resolver version, and an
optional matched catalog ID and catalog fingerprint. Existing readers already
ignore additional payload keys. No SQL table/column changes are needed, so
`PRAGMA user_version` remains 1; future structural changes still require numbered
transactional migrations. Missing provenance on a historical flag does not make
it safe to overwrite that flag.

The repository supplies the catalog to `DiaryEngine` inside `BEGIN IMMEDIATE`.
Imports save their reusable snapshot (if applicable) and diary entry together.
Entry payloads, ingredient rows, denormalized `processed_meat` / `red_meat` chart
columns and the existing HealthKit work queue commit together. Resolution never
replaces the UI's entire cached diary or rewrites a live database file. Quick-log
writers use this same engine. Catalog files are immutable and separate from the
authoritative diary; no network lookup or new dependency is involved.

The boolean SQL columns mean **confirmed presence**, not known absence. Unknown
per-food values remain nullable in payloads. Trends reports entries with unknown
flags for the selected focus areas; chart rendering does not perform inference.

## Matching and review

Catalog matching accepts existing source identity or barcode first. Name search
is bounded at 80 candidates; a truncated non-exact result set cannot establish
consensus. Only exact normalized names, comma-delimited ingredient heads, and a
small explicit alias list qualify. Qualifiers such as meatless, turkey, broth,
seasoning, raw and cooked constrain matches. A word buried in a mixed dish is
not an ingredient identity match. Multiple qualifying preparations can supply
the same meat flag without assigning one preparation's ID or nutrition.

Name rules can establish presence from an obvious name such as Bacon. They do
not turn arbitrary unrecognized names into two false flags. Negated/flavored
names remain unknown unless a suitable catalog match supplies evidence. A
compound dish name mentioning bacon alone cannot rule out other meat. Catalog
and name-rule disagreement leaves that field unresolved. This is conservative
matching, not general recipe understanding.

Automatic values are recalculated after a food-name change; deliberate user or
import values are retained. Review screens display the automatic suggestion and
warn about conflicting explicit values. Changing one flag does not implicitly
erase the other. Unknown values do not block food logging. Nutrition and portion
replacement and automatic merging of duplicate foods are intentionally excluded.

## Historical correction

Settings → Food & Meals → Review Classifications explicitly scans all history,
including entries older than the presentation cache. This on-demand operation
can take longer on large diaries; normal launch does not run it. The list shows
distinct food snapshots with useful missing/conflicting classification suggestions.
Unrecognized foods without a suggestion are not silently corrected.

Choosing **Approve Suggestion** or confirming **Approve All (N)** first creates and validates a SQLite
backup under `CalorieTracker/ClassificationBackups/<UUID>.sqlite`, using the
repository's SQLite backup API. This is an on-device recovery copy, not cloud
sync or a substitute for an off-device export. Backup failure prevents correction.

Approve All captures exactly the displayed suggestions, shows their count, and
asks for confirmation that existing explicit classifications may be replaced.
It creates one backup for the entire batch, not one backup per suggestion.
Unknown fields with no suggestion and explicit meal-level overrides remain unchanged.

The correction then reads the indexed food scope in a fresh transaction and
compares each snapshot to the reviewed value. Only still-matching snapshots in
history, ingredients, favorites and the personal library are changed. If any
suggestion no longer has a matching snapshot, the entire batch fails without
applying any corrections, and the UI reloads the list. No partially approved batch
is left behind. Batch scopes bind one JSON array of food IDs so large reviews do
not exceed SQLite's SQL-variable limit. Corrections run in a single pass over the
original snapshots; one correction cannot become the input of another. IDs, order, nutrition,
portions, remembered quantities, and explicit meal overrides are retained.
Changed meal aggregates and SQL chart columns are refreshed atomically. No blanket
rewrite of legacy false values occurs. `DiaryJSONMigration` remains lossless and
does not call the resolver.

## Other review candidates (not implemented in this change)

The current categories are processed meat and unprocessed red meat. Two related
classification reviews would fit this screen next:

- **Unresolved foods:** list foods whose categories still cannot be inferred,
  with manual Yes/No choices. These are requests for input, not approvable
  guesses, so Approve All must exclude them.
- **Meal override conflicts:** flag an explicit meal-level value that disagrees
  with its ingredients. Offer to keep the override or return to ingredient-derived
  classification. Do not silently clear those overrides during food correction.

**Missing fiber** is a useful separate data-completeness review: the model already
distinguishes unknown fiber from zero. A future suggestion should require an exact
catalog identity (or user-confirmed match) and a verified gram/serving basis,
update affected ingredient and entry totals, and preserve explicit values.
Name-only classification agreement is not sufficient evidence for a fiber amount.
Because this changes nutrition rather than just classification, it is deliberately
outside the current Approve All operation. Automatic calorie/macro replacement and
alcohol inference are also excluded.

## Verification

- `make test`: import decoding, missing/explicit flags, qualifiers, ambiguous
  identity, unchanged nutrition, manual overrides, meal edits, historical review,
  stale and duplicate batches, single-backup approval, backup failure, large food-ID
  scopes, SQLite reopening, quick logging and unknown-chart counts.
- `make storage-test`: on-host repository checks, including atomic import rollback,
  ingredient payload / SQL-column agreement and post-edit chart-column updates.
- `make catalog-test`: bacon/cold-cut/ham sandwiches versus bakery and meatless
  exceptions. `make catalog` reproduces the catalog from cached upstream inputs.

The September 2 catalog audit changed six false-negative sandwich classifications:
USDA IDs 170312, 170313, 170315, 170696, 170707 and 170712. It preserved all 14,480
food identities and every non-meat field, including nutrition and portions.
