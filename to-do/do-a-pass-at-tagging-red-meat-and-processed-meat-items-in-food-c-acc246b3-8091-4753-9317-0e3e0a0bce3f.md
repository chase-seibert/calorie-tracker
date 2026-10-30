## User requirements

- As a user, I want the bundled catalog's red-meat and processed-meat tags reviewed and populated across its food sources, so that meat tracking reflects the foods represented by the catalog.
- As a user, I want red meat and processed meat classified independently, so that foods containing both kinds of meat can carry both tags.
- Scope assumption: “food catalog” includes USDA, Open Food Facts, and curated Chase Food rows. The checked-in catalog currently has no positive flags for any Chase Food row, so the review must fill that gap using source data keyed by stable Chase Food IDs. This is a catalog data-quality pass, not an in-app editing flow.
- Classification should follow the definitions in `docs/product-requirements.md`: processed meat includes preserved meat from red meat or poultry; red meat means unprocessed mammalian meat. Preserve the current treatment of mixed foods where evidence supports both, and avoid inferring meat presence from incidental words or non-meat products.

## Architecture and data model

- The builder derives USDA flags from food categories and FNDDS ingredient recipes, and OFF flags from category/ingredient tags plus token-aware name rules. Chase Food rows currently default both SQLite flags to false because the canonical source has no classification fields.
- Add a readable, stable-ID keyed Chase Food classification source and project its two independent fields through `scripts/prepare_chase_food_data.py` and `scripts/build_food_catalog.py`. Keep the existing SQLite columns and `CatalogStore` behavior. No app persistence, diary schema, migration, nutrition, or search behavior change is required.
- Treat the flags as independent presence classifications. Processed meat includes cured, salted, smoked, fermented, dried, or otherwise preserved meat from red meat or poultry; red meat means unprocessed mammalian meat. For composite foods, classify from documented composition or reliable source evidence, not merely an optional topping or a suggestive name. Leave ambiguous cases untagged and document the decision boundary.

## Basic test cases

- Chase Food staples such as plain beef, pork, and lamb are tagged red meat; clearly cured items such as bacon, ham, pepperoni, and salami are tagged processed meat. Poultry-only processed items do not receive red meat.
- A Chase Food composite receives a tag only when the catalog's default recipe/profile includes that meat. An optional burger topping or optional sandwich filling does not make the base food inherently tagged.
- A documented mixed composition can receive both flags. Meatless analogues, buns, and foods with only incidental flavor, broth, extract, fat, or uncertain ingredient evidence do not become false positives.
- USDA category/ingredient and OFF category/ingredient logic is tested separately, including its existing token and non-meat exceptions.
- Rebuilding changes only intended flags for reviewed stable identities; source IDs, nutrients, portions, aliases, options, and unrelated records remain unchanged. Old generated catalog data without classification fields continues building with both flags false.

## High-level implementation details

1. Inventory all three sources by stable identity and audit likely Chase Food positives against each canonical record's documented base composition and nutrition/source evidence. Treat the current zero flags for all 532 Chase Food rows as a missing source-data feature, not as proof that every food is meat-free.
2. Create a concise, human-reviewable classification source keyed by `food_id`, covering positive values and explicit decisions for ambiguous composite foods. Keep processed and red-meat values separate; do not infer optional customization choices as part of a base food.
3. Update the Chase Food preparation and catalog build steps to carry the source values into the existing SQLite columns. Add focused regression fixtures for plain meat, processed meat, poultry, both-tag composites, meatless foods, and optional-only ingredients; only change USDA/OFF rules where catalog review demonstrates a specific miss or false positive.
4. Rebuild through `make catalog`, run `make catalog-test`, and compare before/after flags by stable source identity. Verify unchanged nutrients, portions, aliases, options, and IDs; update the taxonomy/data-source documentation to describe the new classification source and its boundaries.
5. Main risks are over-tagging customizable composite foods, source rule false positives, and generated artifacts obscuring the actual durable change. Review the exact identity-level diff, keep uncertain entries conservative, and do not refresh or download upstream data as part of this pass.
