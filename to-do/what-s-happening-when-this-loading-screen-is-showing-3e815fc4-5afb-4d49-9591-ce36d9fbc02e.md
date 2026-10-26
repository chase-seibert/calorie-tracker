## User requirements

- As a user, I want the startup loading screen to say what the app is doing while it opens my diary, so that I can tell whether it is making progress or waiting on something.
- As a user, I want a clear failure message and retry action if the diary cannot be opened, so that I know what happened and can try again without risking my saved data.
- Assumption: show named phases and, if useful, elapsed time; do not imply a numeric percentage when the work has no reliable total. The screenshot shows the iPhone “Opening diary…” screen.

## Architecture and data model

- Keep the existing `DiaryStore` and `DiaryRepository` flow. Publish a small, transient loading phase (and optionally a start time) from the store so the UI can explain opening, preparing, reading the diary snapshot, and calculating the streak. Reset it on success, failure, and retry.
- Coordinate the app-level launch gate in `CalorieTrackerApp` with the store state. The same generic label currently appears before `RootView` is ready and as its overlay; startup follow-up work can also keep the first screen up after diary loading. Represent that work clearly or complete it outside the diary-opening phase so the message stays truthful.
- Keep storage, migration behavior, and persisted data unchanged. No schema, migration, catalog, or diary-content changes are required. Continue to show storage errors and retry without replacing an unreadable existing diary with an empty one.

## Basic test cases

- On a normal cold launch, observe the loading message change through the actual diary-opening phases and disappear once the diary is ready; controls remain unavailable until a snapshot is published.
- On a first launch that converts a legacy diary, show an opening/preparing state until conversion and loading finish, then display the existing diary contents.
- With a deliberately slow repository operation, confirm the screen stays responsive and the displayed phase reflects the operation in progress; elapsed time, if included, increases monotonically.
- With a corrupt or unsupported database or missing shared container, stop the loading state, show the existing actionable error and Retry control, and leave the original data untouched.
- Retry after correcting the storage problem and confirm the phase restarts, the diary loads, and the failure state clears.
- Verify returning from background does not show a stale phase or start overlapping reloads.

## High-level implementation details

1. Trace cold-launch gating and reload behavior in `CalorieTracker/App/CalorieTrackerApp.swift`, `CalorieTracker/Views/RootView.swift`, and `CalorieTracker/Data/DiaryStore.swift`; map user-facing phases to the actual awaited work in `DiaryRepository` (open/migration, prepare, snapshot, streak).
2. Add transient, main-actor-observable phase state to `DiaryStore` and update it at those boundaries, including failure and retry paths. Keep the state descriptive and indeterminate; do not add persistence or expose sensitive diary contents in status text or diagnostics.
3. Update both startup and root loading presentations to consume the same state. Account explicitly for launch follow-up work such as weekly-report catch-up so the app does not keep saying the diary is opening after the diary is already available.
4. Preserve the existing unavailable-data safeguards, error detail, and retry behavior. Avoid making onboarding, deep-link handling, or diary actions available before a valid snapshot exists.
5. Add focused store/UI coverage for phase transitions, successful load, load failure, retry, and relaunch/background behavior. Verify with the repository’s focused test workflow and inspect the iPhone launch UI; keep build, test, and physical-device launch evidence distinct.
6. Decide during implementation whether elapsed time adds enough value beyond phase labels, and whether weekly-report catch-up belongs on the startup screen or should run after the diary is usable. No timing threshold or progress percentage is specified by the task.
