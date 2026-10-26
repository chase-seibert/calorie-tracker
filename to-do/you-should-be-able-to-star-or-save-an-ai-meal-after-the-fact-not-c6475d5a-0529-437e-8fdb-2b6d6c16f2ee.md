## User requirements

- As a user, I want to save a previously logged AI-estimated meal from its diary detail, so that I can reuse it later without having to choose Save while importing it.
- As a user, I want to star a previously logged AI-estimated meal from its diary detail, so that I can find it in Favorites for quick logging.
- Assume “save” adds the meal to the existing reusable meals collection and “star” also marks it as a favorite. Keep imported meals identified as imported so they remain separate from hand-created meals in the Personal Library. Preserve the current optional save-at-import behavior.

## Architecture and data model

The app already retains one-off logged meal ingredient snapshots in `DiaryEntry.mealItems`, stores reusable meals in `DiaryDocument.meals`, and stores meal favorites by stable ID in `favoriteMealIDs`. SQLite already persists these collections and their ingredients. Reuse those paths: promote a logged snapshot to one reusable imported `SavedMeal`, then optionally favorite it. Preserve the component foods, amounts per serving, name, notes, and meat overrides from the logged entry; keep the diary entry’s logged amount, nutrients, and ingredient snapshot intact. Repeated save/star actions should resolve to the same reusable meal instead of creating duplicates.

No new schema or migration appears necessary. Confirm whether promotion should associate the diary entry with the new saved meal ID; existing linked saved-meal edits refresh linked history, while the diary entry also carries its own snapshot. Preserve current history semantics and make the association choice explicit in implementation.

## Basic test cases

- Import and log an AI meal without selecting Save to Saved meals. Open that diary meal afterward and verify Save and Favorite are available.
- Save it after logging; verify it appears in the imported meals section for later logging and remains out of hand-created Personal Library meals.
- Star it after logging; verify it appears in Favorites, can be unstarred, and remains available for repeat logging.
- Repeat Save or Favorite on the same diary meal; verify there is one reusable meal with a stable ID and no duplicate favorite.
- Promote a meal after changing its logged serving amount or editing its ingredient snapshot; verify the reusable meal reflects the reviewed per-serving components and the existing diary totals and history remain unchanged.
- Save/star a previously logged meal after closing and reopening the app; verify the reusable meal and favorite state persist.
- Attempt promotion for an unavailable or invalid meal snapshot; show an actionable error and leave diary and library data unchanged.

## High-level implementation details

1. Trace the logged-meal actions in `MealDetailView` and the corresponding async mutations in `DiaryStore`. Add post-log Save and Favorite actions only for imported one-off entries that do not already resolve to a reusable meal; retain the existing favorite/unfavorite behavior for saved meals.
2. Add a focused `DiaryEngine` operation that validates the current entry, derives a normalized per-serving `SavedMeal` from its snapshot, preserves imported origin and metadata, and safely handles repeated requests. Route persistence through the existing repository scopes and SQLite collection updates.
3. Decide and document whether promotion links `savedMealID` to the entry. Check `updateMealEntry` and `updateSavedMeal` together so later serving edits and template edits cannot silently discard intentional logged snapshots or change history unexpectedly.
4. Add engine/repository and UI coverage for one-off import promotion, favorite toggling, duplicate prevention, snapshot preservation, invalid entries, and persistence across reload. Update `docs/design.md` and `docs/product-requirements.md` to describe the after-the-fact actions and imported-meal placement.
5. Verify the relevant focused tests and the repository’s supported test/build path during implementation; then attempt `make phone-deploy` as required by the repository. Report simulator, signing, device, or launch evidence separately.
