## User requirements

- As a user, I want to describe a meal and get an AI estimate without taking or selecting a photo, so that a description alone is enough when it gives useful detail.
- As a user, I want to add a photo when it helps, so that I can provide either input or both without making the camera or photo library mandatory.
- As a user, I want the meal description at the top and the main inputs and Analyze action together in a compact screen, so that logging takes less scrolling.
- Assumptions: require a nonblank description only when no photo is supplied; keep photo-only analysis available. Analysis continues to produce an editable review and must not log a meal automatically.

## Architecture and data model

No material persistence, diary schema, or migration change is required. The current flow returns a validated `CustomMealFile`, reviews it in `CustomMealImportView`, then logs through the existing `DiaryStore.logImportedMeal` path.

The analysis request currently requires a JPEG and treats the text as optional context. Extend the request/client contract to accept a required usable input set: description, optional image, or both. Include the description as untrusted user input in the prompt; add the image content only when one is present. Keep the bounded Responses API call, strict structured output, local meal validation, Keychain credential handling, cancellation, and explicit retry behavior. Update the disclosure so it accurately names the inputs sent to OpenAI.

## Basic test cases

- Enter a nonblank description with no image: Analyze is enabled, the request contains the description and no image, and a valid response opens the existing review screen.
- Add a photo with no description: photo-only analysis remains available and sends the image; adding both inputs sends both.
- Leave both inputs empty or enter only whitespace: Analyze is disabled and no request is made.
- Reach the description length limit: input remains bounded and the displayed count matches the accepted text.
- Return malformed or unestimable output, or encounter a network/API error: no meal is logged; the description and selected photo remain available for an explicit retry, with existing error and usage-help behavior retained.
- With the keyboard dismissed on a typical iPhone, the description appears first and the input controls and primary Analyze action fit without a long scroll; smaller layouts remain scrollable and operable with accessibility text sizes and VoiceOver.
- Review and log a valid estimate: the user can inspect/edit it, it uses the selected diary date, and the existing one-off or saved-meal behavior is unchanged.

## High-level implementation details

1. In `CalorieTracker/Views/MealPhotoAnalysisView.swift`, make the description the first and primary input, relabel it as the meal description, and make photo selection/capture optional supporting controls with a compact preview. Rework the current photo-first `Form` layout so the primary action is readily visible when the keyboard is dismissed, while preserving scrolling and accessibility on smaller screens.
2. Rename photo-specific action, progress, navigation, accessibility, and analytics presentation where needed to describe meal analysis. Keep camera permission and image preprocessing conditional on a photo being supplied.
3. In `CalorieTracker/Data/OpenAIMealAnalysis.swift`, adapt `MealAnalysisRequest` and `MealAnalysisClient` for text-only, photo-only, and combined requests. Preserve the current input bounds, strict response schema, response validation, request limits, and no-automatic-retry behavior; do not create a second response or diary data model.
4. Preserve the handoff to `CustomMealImportView` and its validated edit-before-log flow. Update `CalorieTrackerTests/CalorieTrackerTests.swift` request tests for all three input combinations and empty-input rejection, plus the relevant boundary/failure coverage. Update user-facing privacy copy and any source-specific analytics names to match text-or-photo analysis.
5. Verify with focused request/UI tests and the repository's supported build workflow (`make test`, `make sim-compile` when simulator services are unavailable); for implementation completion, attempt `make phone-deploy` and report launch separately from build/install. No application verification is part of this plan-only task.
