# Analyze meal photos in-app with the OpenAI API

StageChase project: `03ee492c-9d71-4f8c-b778-afd96fea4610` (Calorie Tracker)  
Task: `c2f924e5-bb2c-41d8-a269-5efaf17a3d87`  
Scope: implementation plan only. Leave the task incomplete in Planned.

## User requirements

- Start in Yum Chase, take or select a meal photo, optionally describe the portion or preparation, analyze it with the OpenAI API, review the estimated components, and explicitly log the meal. Eliminate ChatGPT app switching and manual attachment sharing from this flow.
- Keep portions, calories, macros, optional fiber, meat classifications, and uncertainty editable through the existing meal review. Include plausible oils, butter, dressings, and sauces without double counting. The estimate is not a measured nutrition result.
- Preserve the chosen diary date, including past dates and a request that crosses midnight. Analysis alone must not save a meal or write to the diary or HealthKit.
- Keep existing `.calmeal` file imports available. API responses use the same meal contract internally; no downloaded attachment or new public import format is necessary.
- Provide clear API setup, separate usage billing information, progress, cancellation, and recoverable errors. An OpenAI API credential is required; the ChatGPT app subscription is not the credential for this integration.
- Planning assumption, not a confirmed user preference: first version is a privately deployed personal app using an owner-entered OpenAI API key in device Keychain. Do not embed a developer/shared key in the app. See the credential boundary below before distributing this design to others.
- Exclude Apple Shortcuts integration, a ChatGPT conversation browser, multi-photo analysis, background analysis queues, automatic logging, and food-component library/ranking changes. The existing StageChase task “Save AI meal constituent foods and rank them in future searches” remains separate.

## Architecture and data model

### Current integration points

| Existing source | Role in this change |
| --- | --- |
| `CalorieTracker/Views/FoodPickerView.swift` | Add an accessible Analyze Photo entry alongside existing logging choices; retain the supplied `date` and catalog behavior. |
| `CalorieTracker/Views/DiaryView.swift` | Owns the selected diary date and Log food presentation; coordinate dismissal back to that day after a successful log. |
| `CalorieTracker/Views/SettingsView.swift` | Add OpenAI setup under Connections and update the existing AI import guide/privacy descriptions. |
| `CalorieTracker/Models/CustomImportFile.swift` | Reuse `CustomMealFile`, `CustomFoodDefinition`, validation, normalization, and component-derived totals. Extract common nutrition instructions from the attachment-specific prompt. |
| `CalorieTracker/Views/CustomMealImportView.swift` | Reuse editing and explicit Log. Parameterize target date and source/presentation; current implementation uses `Date()` and file-import analytics. |
| `CalorieTracker/Views/RootView.swift` | Preserve incoming file routing and its default-to-today behavior while sharing review presentation safely. |
| `CalorieTracker/Data/DiaryStore.swift`, `DiaryEngine.swift`, `DiaryRepository.swift` | Reuse the existing atomic imported-meal snapshot and diary write path. |
| `CalorieTracker/Info.plist` | Camera permission text currently mentions only barcode scanning; include meal photography. |

Add small testable components, using Swift concurrency, Foundation networking, Security, PhotosUI, and the existing UIKit/SwiftUI boundary. Avoid adding an SDK dependency solely for one HTTP endpoint:

- `MealAnalysisClient` protocol and `OpenAIMealAnalysisClient`: one bounded request returning a validated `CustomMealFile` plus non-content request metadata.
- `MealPhotoPreprocessor`: downsample, normalize orientation, re-encode to JPEG, and remove source metadata before upload.
- `OpenAICredentialStore`: Keychain load, replace, and delete behind an injectable interface.
- `MealAnalysisViewModel` and view: capture/select → preview/context → analyzing → review or error. Keep one request generation ID so a cancelled or superseded result cannot replace a newer draft.
- Request/response DTOs and a versioned strict JSON schema separate from persistent diary models. No database migration is expected.

### Credentials and privacy boundary

The personal variant sends HTTPS requests directly to the fixed OpenAI API host using an owner-provided key. Store it as a non-synchronizing, app-private Keychain item accessible only while unlocked on this device. Never put it in UserDefaults, the diary, App Group storage, app bundles, Git, analytics, screenshots, or fixtures. Settings offers a secure entry field, masked configured state, Replace, and Remove. Do not automatically contact OpenAI when saving a key or opening a screen; credentials are verified by an explicitly initiated analysis. No real key is needed to implement mocks or write tests.

OpenAI's documented recommendation is to keep API keys on a server, not in client apps. Keychain protects this personal credential at rest but does not make a client-held credential server-secret. If this app is distributed or uses a shared developer key, replace the direct adapter with an authenticated backend that owns the OpenAI key, enforces user authorization and request/cost limits, and validates uploads. Do not ship a shared key or an unauthenticated generic API proxy. Hosting is outside this personal version's implementation scope.

Before Analyze, show the photo and context being sent and identify OpenAI as the processor. Send only those inputs and the fixed meal instructions, never the diary, HealthKit history, other photos, or analytics identifiers. Use an ephemeral URLSession without response caching, `store: false`, and inline image data rather than a separately uploaded persistent Files object. Explain that disabling response storage is not a promise of zero provider retention. Retain the draft only for the foreground flow; discard image bytes, generated output, and temporary files when the flow ends. Do not auto-save a camera image to Photos.

### Request, response, and cost controls

- Use `POST https://api.openai.com/v1/responses` with text plus one `input_image`, and `text.format` set to a strict JSON schema. Do not enable tools, web search, code execution, conversations, background mode, or recursive correction calls.
- Select a currently supported vision model with Structured Outputs during implementation. Keep its identifier in one configuration location; record the tested model and current pricing in setup documentation. Do not promise the same model, memory, or estimates as a personal ChatGPT conversation. Start with a single documented model rather than an arbitrary model/endpoint editor.
- Initial engineering limits: one photo; source file up to 25 MiB with a decoded-pixel safety check; downsample before full-resolution materialization to a 1,600-pixel longest edge; encoded JPEG up to 2 MiB; context up to 2,000 characters; 8,000 maximum output tokens; 90-second overall request deadline; 1 MiB transport response limit and 256 KiB extracted meal JSON limit. Treat these as initial settings to verify against image quality and latency, not API platform limits. Enforce transport bounds while reading, not only after allocating an entire unbounded response.
- Permit one in-flight request per flow and disable repeated Analyze taps. No automatic paid retries or queued work after relaunch. A user retry makes a new paid analysis attempt and says so; cancellation stops local waiting but cannot guarantee that provider processing or charges stop. Cancel on dismissal/backgrounding and offer an explicit retry on return.
- Parse the Responses envelope by output/content type, not a fixed array index. Handle refusals, failed or incomplete status, truncated output, missing content, and unsupported-model errors before decoding meal JSON. Model text is data and cannot select endpoints, execute actions, or bypass Log.
- Strict schema objects use `additionalProperties: false` with all declared keys required; represent optional notes, fiber, and meat flags as nullable. Decode null to existing optional fields, preserving unknown rather than converting it to zero/false. Use the meal format identifier/version and locally revalidate all numerical and component bounds even after schema-constrained generation.
- Share the existing meal-estimation rules while keeping the attachment prompt's filename/download instructions out of the API prompt. For non-food or unusable images, support a structured `cannot_estimate` result in an internal envelope with a reason and nullable meal, rather than inventing nutrition. Validate success/error consistency locally; the public `.calmeal` format remains unchanged.
- Map missing/invalid credentials, permission denial, unavailable camera, offline/timeout, rate limiting, exhausted billing quota, upstream failure, refusal, and invalid data into distinct actionable UI states. Do not display raw server bodies or authorization headers. Keep the selected photo/context while showing a foreground error so the user can correct or retry.

### Review and persistence

Pass the valid meal and captured target date to the existing review, labeled Review Meal for API results. Use a source value such as `openai_photo` for content-free operational analytics instead of claiming a file import. Reuse local classification suggestions, user overrides, and totals derived solely from components. The review's Log action is disabled while saving; a failed write keeps the draft and edits available. A second tap or a late network callback must not create a duplicate entry.

Preserve the existing imported reusable snapshot/Recent behavior, ingredient snapshots, break-apart, and HealthKit handling through `DiaryStore.logImportedMeal`. Do not copy SQLite files or add a new storage engine. The current review's save-for-reuse toggle is not forwarded as a parameter to `logImportedMeal`; verify its effective behavior and do not promise a persistence choice the shared path does not implement. Any necessary repair to shared review semantics should be narrowly scoped and covered for both file and API entry points.

## Basic test cases

1. A single-food and a multi-component mocked response decode, normalize, total correctly, and open editable review without any diary writes; Log commits once to the originally selected date.
2. Nullable fiber and meat flags remain unknown. Negative/nonfinite or excessive nutrients, unsupported versions, empty/over-50 component lists, malformed envelopes, oversized responses, refusals, incomplete output, and `cannot_estimate` never become diary entries.
3. Request fixtures verify inline image content, selected model, strict schema, `store: false`, output cap, no tools, and no unrelated diary/health data. A meal with likely oil retains uncertainty and avoids duplicated calories; local validation cannot prove estimate accuracy.
4. Camera denial/unavailability, photo-picker cancellation, huge/corrupt/rotated/HEIC images, and EXIF location metadata are handled without uploading unreviewed source bytes. Simulator testing uses supplied fixtures rather than claiming camera coverage.
5. Fake networking covers 401/403, billing quota/rate-limit 429 variants, 5xx, timeout, network loss, refusal, cancellation, and late success after a new request. Repeated taps do not issue duplicate calls; there are no implicit paid retries.
6. Keychain tests cover absent key, replace/delete, locked/unavailable storage, and failures without echoing secrets. Network and analytics mocks verify credentials and meal/photo/context content do not enter logs.
7. Review edits, unknown classifications, selected historical day, midnight rollover, cancellation, failed save, and repeated Log taps behave correctly. Reload preserves component snapshots, Recent access, and break-apart. Existing `.calmeal` validation and imports remain compatible.
8. UI fixtures cover unconfigured setup, photo preview/context, analyzing/cancel, each major error category, and populated review with no API calls. Add a focused Makefile target if a reusable UI test workflow is missing.
9. With an owner-configured key, make a small explicitly initiated live acceptance request on the phone. Verify actual photo submission, valid review, edited log, relaunch persistence, cancellation, and observed latency/usage. Do not put credentials in test arguments, shell commands, or screenshots; report live checks as unverified if credentials are unavailable.

## High-level implementation details

1. Confirm the personal credential assumption and recheck current model support/pricing before implementation. Preserve iOS 18 deployment support; this API flow does not require Apple Intelligence. Register new source/test files in the Xcode project as needed without adding API/network or credential code to widget targets.
2. Extract shared meal decoding/validation and nutrition instructions. Keep the URL loader's security-scoped access and `.calmeal` extension gate intact; add an in-memory decoder for API data without weakening file validation. Implement/test the strict internal response envelope and nullable mapping.
3. Implement the injectable Keychain store, bounded photo preprocessing, and non-streaming-in-the-UI API adapter with a bounded network reader. Add deterministic URLProtocol/client mocks and fixture data first.
4. Add Settings configuration and the food picker's Analyze Photo flow with preview, optional context, explicit submission, progress, cancellation, and actionable errors. Update camera permission copy and avoid broad Photos library permission when PhotosPicker suffices.
5. Parameterize shared review date/source and coordinate sheets/navigation. Reuse validated meal logging and classification, and verify save-for-reuse behavior against current code and tests. Protect the in-flight save and keep user edits on errors.
6. Update `docs/custom-import-files.md`, `docs/architecture.md`, `docs/setup-install.md`, relevant privacy UI, and `docs/analytics-events.md` for the final implementation. Document API billing and credential setup without embedding keys or asserting a fixed cost. Keep developer implementation details out of the normal photo flow.
7. Run focused tests and `make test` with host-side permission per repository guidance; use `make sim-compile` and explicitly mark simulator tests unverified if host execution is unavailable. Run `make storage-test` when shared persistence is changed. Inspect fixture UI, then always attempt `make phone-deploy` for implementation completion, following `docs/sqlite-storage.md` and installing over the existing app. Report actual build/install/launch/live-API results separately.
8. For this planning task, verify the saved Markdown, finish the planning run, attach this exact path, and explicitly move the task to Planned while leaving it incomplete. No application edits, builds, or phone deployment are part of producing this plan.

### Official references checked for this plan

- [OpenAI image inputs and vision](https://developers.openai.com/api/docs/guides/images-vision): photo analysis and image input forms.
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs): strict schema, nullable fields, and refusal handling.
- [API authentication](https://developers.openai.com/api/reference/overview): bearer credentials and server-side secret recommendation.
- [API data controls](https://developers.openai.com/api/docs/guides/your-data): response storage and provider retention limitations.
- [API pricing](https://developers.openai.com/api/docs/pricing): verify model and image/token charges during implementation.
