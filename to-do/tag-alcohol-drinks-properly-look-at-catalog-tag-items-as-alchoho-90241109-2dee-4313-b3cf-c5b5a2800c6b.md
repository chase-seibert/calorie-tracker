## User requirements

- As a user, I want catalog items that are alcoholic drinks tagged consistently, so that alcohol-related foods can be identified accurately.
- As a user, I want the entire food catalog reviewed from a serialized, stable-ID list by an LLM, so that candidate alcoholic items are found across the catalog rather than only by a name search.
- Scope assumption: “alcohol” means a beverage intended to be consumed as an alcoholic drink. Non-alcoholic beer, root beer, ginger beer, juice cocktails, extracts, and foods merely cooked with alcohol should not be tagged as alcoholic drinks unless the product requirement is clarified.
- The existing Alcohol feature records a daily drink count separately from food entries. This plan covers catalog metadata; it does not assume a new logging flow or change to diary alcohol tracking.

## Architecture and data model

- The catalog builder already combines USDA, Open Food Facts, and Chase Food records into `FoodCatalog.sqlite3`; `foods` has independent meat classification columns, but no alcohol field. `CatalogStore` maps those columns into `Food`.
- Export a complete review manifest containing source, stable source ID, name, brand, relevant source category, and (for Chase Food) default included components. Ask the LLM to return candidate labels by source and ID with a brief rationale; reject unknown/duplicate identities and review ambiguous suggestions against source evidence before committing tags. Preserve the input manifest and the curated result so the pass is reproducible.
- Add a source-ID keyed alcohol classification file with an explicit boolean and evidence/basis, and apply it in the catalog build pipeline. Add a `contains_alcohol` or equivalently named column to the generated SQLite catalog and map it through `CatalogStore` into `Food`. Regenerate the bundled catalog; no diary database migration is indicated for this catalog-only field. If snapshots are later expected to retain or act on this tag, decide that separately and preserve decoding of existing diary files.
- Do not add runtime LLM/network calls. The existing daily `AlcoholEntry` model and its calories/trend behavior remain separate. Decide during implementation whether “contains alcohol” means only alcoholic drinks or all foods/ingredients containing alcohol; this plan assumes drinks only because that matches the task wording.

## Basic test cases

- The serialized manifest includes every catalog identity exactly once and retains source plus source ID, including duplicate display names from different sources.
- The LLM result parser accepts known stable identities and rejects malformed rows, duplicate identities, and IDs absent from the manifest.
- Known alcoholic drinks such as beer, table wine, spirits, and alcoholic cocktails receive the positive tag; non-alcoholic beer, root beer, ginger beer, juice cocktails, and non-drink foods remain negative under the agreed definition.
- A Chase Food composite is classified from its default drink identity/composition, not optional additions; an Open Food Facts product is distinguished by its own source ID even when its name matches another record.
- A catalog rebuild writes the curated flags to SQLite and `CatalogStore` returns the same value; unrelated IDs, nutrition, portions, search fields, and existing meat classifications remain unchanged.
- Older catalog rows and diary snapshots without the new field remain readable; no runtime lookup calls an LLM.

## High-level implementation details

1. Trace `scripts/build_food_catalog.py`, `scripts/prepare_chase_food_data.py`, `CalorieTracker/Data/CatalogStore.swift`, and the `Food` model to confirm the catalog record paths and define one stable identity format shared by export, review, and import.
2. Add a reproducible serializer for all catalog records. Include names and useful source/composition context, but avoid sending irrelevant nutrition fields unless the classification review shows they help distinguish alcoholic drinks. Record the serialized manifest used for the LLM pass.
3. Prompt the LLM to return only source-ID keyed candidates, explicit yes/no decisions, and concise rationale. Validate its output mechanically, then manually review positives and likely false positives against canonical records; keep uncertain items untagged and document the chosen alcohol boundary.
4. Add the curated classifications to the repeatable catalog input/build path, add and populate the SQLite column, and update `CatalogStore`/`Food` mapping plus the catalog review export if that remains a supported audit surface.
5. Add focused catalog tests for identity validation, positive/negative beverage boundaries, generated SQLite values, source collisions, and unchanged non-classification fields. Run `make catalog`, `make catalog-test`, and the repository-required app build/deploy checks only if the implementation changes app code; verify the identity-level catalog diff before accepting generated artifacts.
6. Update the catalog taxonomy documentation with the field meaning, source file, LLM-assisted review process, evidence expectations, and exclusions. Main risks are classifying non-alcoholic drinks or alcohol-flavored foods as alcoholic beverages, and allowing regenerated upstream rows to drift from reviewed classifications.

Unresolved decision: confirm whether the tag denotes an alcoholic beverage (assumed here) or any food containing alcohol, and whether the app should consume this catalog flag in a user-facing workflow.
