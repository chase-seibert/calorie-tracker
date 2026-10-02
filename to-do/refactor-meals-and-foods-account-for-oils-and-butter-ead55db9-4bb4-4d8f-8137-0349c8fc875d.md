# Refactor meals and foods; account for oils and butter

## User requirements

- As a user, I want `.calmeal` to be the only supported import format for AI-generated food and meal estimates, so that I can review and log them through one consistent flow.
- As a user, I want meal estimates to account for likely added butter, cooking oils, dressings, and sauces, so that the logged calories and macros better reflect what was eaten.
- As a user, I want meal components and their nutrition retained when useful, so that I can review, edit, repeat-log, or break apart the meal in the diary.
- As a user, I want each generated attachment to have a unique filename based on the meal name, so that repeated estimates do not overwrite or confuse one another.

Use the existing `.calmeal` JSON contract as the sole supported import format. The assistant should always produce one named meal with one or more food components, including a single component for simple foods. Generate a fresh, collision-resistant filename each time from a normalized meal-name slug plus a unique suffix, retaining the `.calmeal` extension. Estimate added fats only when plausible from the dish or preparation; call out uncertainty and avoid counting an ingredient twice.

## Architecture and data model

Keep the existing meal payload as the sole external import contract. Remove the food-only payload and dispatch path; `.calmeal` remains a validated, named meal with food components and opens the meal review flow. `RootView` should route only that payload to the review sheet. Generate a unique, meal-name-based attachment filename on every prompt use, with the extension matching the supported contract.

No material diary schema or SQLite migration appears necessary if the unified payload still maps to the existing `SavedMeal`/`MealItem` component snapshots and `DiaryEntry` logging path. Preserve current local review, optional save-for-reuse behavior, Recent/quick-log snapshot semantics, and nutrient totals derived from components. Confirm whether simplification should also change those internal semantics before implementation; this request does not specify that.

Update document type declarations and user-facing prompt/onboarding documentation together. Remove `.calfood` support and all references to it from import guidance; reject it as unsupported. Keep `.calmeal` validation, imported meal persistence, and diary history compatibility intact. Do not introduce a diary database migration unless implementation reveals a required change to the existing component snapshots.

## Basic test cases

- Import a generated `.calmeal` with one component; it opens the meal review, shows the estimate, and logs successfully.
- Import a multi-component meal; component portions and nutrition are retained, and the displayed meal total equals the sum of its components.
- Generate a dish plausibly cooked with butter or oil, or served with dressing; the prompt asks for a reasonable estimate and includes a distinct component when calorically material, with uncertainty noted. A dish with no plausible added fat does not receive an arbitrary addition.
- Review and edit an oil, butter, dressing, or sauce component; logging, repeat logging, saving for reuse, and breaking apart the entry preserve the edited totals without double counting.
- Reject malformed JSON, missing required values, invalid nutrition, and an empty or oversized component list with a useful import error and no diary write.
- Reject a valid former `.calfood` attachment with a clear unsupported-format error and no diary write; continue accepting valid `.calmeal` attachments.
- Generate filenames for repeated meals, including names with punctuation or non-Latin characters; each filename is based on a readable normalized meal-name slug, is unique, and retains `.calmeal`.

## High-level implementation details

1. Refactor `CalorieTracker/Models/CustomImportFile.swift` to retain only the `.calmeal` model, validation/conversion path, and assistant prompt. The prompt should name `.calmeal` as the only format, create a unique meal-name-based filename on every generation, estimate likely hidden cooking fats and condiments, include them only when material, and warn about uncertainty and double counting.
2. Remove food-only import dispatch and review handling from `CalorieTracker/Views/RootView.swift` and `CalorieTracker/Views/CustomMealImportView.swift`; preserve the editable meal review, save-for-reuse choice, and existing diary meal path.
3. Update `CalorieTracker/Info.plist` to register only `.calmeal`, and revise the Settings import guide, copied prompt, onboarding copy in `CalorieTracker/Views/RootView.swift`, and `docs/custom-import-files.md`, `docs/product-requirements.md`, and `docs/architecture.md` to describe `.calmeal` as the only supported format. Remove references to the retired format from import UI and documentation.
4. Update focused import/model/view tests for strict `.calmeal` decoding, rejection of `.calfood`, meal totals, unique filename generation (including repeated names), and oil/butter estimates; then run the repository's supported checks. Preserve existing meal snapshot storage unless inspection shows it cannot support this flow.

Risks include removing an import path users may still have saved attachments for, assistant inconsistency in separating aggregate foods from meal components, filename collisions, and double-counting fats already included in a component estimate. Keep the prompt and review totals explicit about component-level estimates so those errors are observable.
