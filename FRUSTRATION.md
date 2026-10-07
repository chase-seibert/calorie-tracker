# Frustration Log

## 2026-10-07: Visible popover controls can miss input or sit offscreen

The cheat-day confirmation drew a capsule outside a plain text Button's label,
so tapping its visible padding never invoked the action. Move all button layout
inside the label and define its content shape. Stress testing found a second
missed-input path: anchoring the popover to the bottom of the full logged-food
list placed the confirmation at y=937 on an 874-point screen. Reuse the fixed
bottom toolbar popover for row taps. Check actual hit areas and onscreen frames
before attributing missing confirmation callbacks to the action queue or SQLite.

For fixture relaunch checks, set `CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE=1`
alongside explicit `CALORIE_TRACKER_FIXTURE=device`. Otherwise the default
simulator demo forces a fresh database even with `CALORIE_TRACKER_FIXTURE_RESET=0`,
which can look like a persistence failure after successful commits.

## 2026-10-06: Storage self-test expected a pre-rename ingredient name

The detached-meal storage self-test compared its logged ingredient to the
original `Bacon` value even though the fixture also sets the diary's custom
food name to `My bacon`. `DiaryEngine` correctly applies that name to the
logged snapshot. Build the expected item with the mapped name before comparing
the round trip.

## 2026-09-02: Concurrent UI tests fought over the default simulator

The snack navigation UI test lost its Settings tap when a separate StrengthLog
run foregrounded its app on the same iPhone 17 Pro simulator. The XCTest log
explicitly switched to `com.cseibert.StrengthLog`; the failure was not a missing
Settings row. Run UI tests on a dedicated simulator with the existing
`SIM_DEVICE_NAME` override when another project is using the default device,
and wait for the destination navigation bar before querying its rows.
The fresh isolated simulator then stalled during XCTest runner startup; its
eventual diagnostic reported an IPC server-died error. Do not count a successful
app build as a UI-test pass, and remove task-created simulators after testing.

## 2026-09-02: AppKit contact sheets need a drawable bitmap format

A 24-bit, three-sample RGB `NSBitmapImageRep` loaded but produced a nil
`NSGraphicsContext(bitmapImageRep:)`. Use a 32-bit, four-sample RGBA bitmap
for the drawing canvas, fill its background, and keep the actual icon exports
opaque. This unblocked the small-size/grayscale icon review sheet.

## 2026-09-02: Classification enrichment changed legacy snapshots

The storage round-trip check caught added provenance on already-classified
legacy ingredient snapshots. Preserve complete pre-existing values and absent
provenance as-is; attach resolution metadata only when resolving missing values
or accepting an explicit correction. Keep JSON conversion free of enrichment.

## 2026-09-01: CoreDevice shared-container listing can omit the live diary

On the owner's phone, appDataContainer listing worked but appGroupDataContainer
showed only Library/Preferences; listing its known CalorieTracker subdirectory
failed. The private JSON was dated August 29 even though the app had newer logs.
Do not treat this listing as evidence that the shared diary is absent or migrate
the stale private copy. The owner authorized an on-device backup/conversion;
its private backup is retrievable independently of shared-container access.

## 2026-09-01: Verification can leave SQLite sidecars behind

Opening a converted snapshot for verification enables WAL. Before publishing a
main file, the migrator switches its isolated candidate to DELETE journaling,
explicitly closes it, and checks that no WAL/journal remains. Apple's SQLite
still left a 32 KB SHM index: that non-authoritative index stays in staging and
is not published. Requiring it to disappear incorrectly rejected a valid
standalone database. Never switch journaling on a live shared store for export.

## 2026-09-01: Asynchronous startup can race onboarding presentation

After moving diary loading off the main actor, constructing `RootView` before
preparing onboarding allowed its default `@AppStorage(false)` to present
onboarding over an existing diary. Accessibility still found covered diary rows,
so a drag test looked like a reorder failure. Inspect the recorded UI before
changing drag code. Startup now gates the root view until the loaded diary has
been checked, and fixture UI tests explicitly opt out of onboarding.

## 2026-09-01: Swift data-write options are not freely composable

Foundation traps rather than throwing when `Data.write` combines `.atomic`
with `.withoutOverwriting`. The diary converter now uses an exclusive manifest
write after validating the staged SQLite database. Never combine these options.
If an attempt stops after publishing the database but before its manifest,
preserve that output and rerun with a new destination; the converter refuses
to overwrite either file.

## 2026-09-01: Standalone Swift and test-report tools need explicit cache paths

Standalone `swiftc` initially tried to write its module cache outside the
workspace. `make diary-tool` uses `build/DiaryModuleCache` so storage checks run
without simulator access. Reading an `.xcresult` can also create a report cache;
use the host-authorized `xcresulttool` path if the restricted read fails.

## 2026-08-24: UniformTypeIdentifiers has no Markdown constant

The current Xcode SDK does not expose `UTType.markdown`. For Markdown files
shared from the app, a custom `FileRepresentation` declared as `.plainText`
compiled but failed while preparing content on a physical iPhone. Writing the
`.md` file before sharing makes attachment creation independently testable, but
`ShareLink` still failed with that verified file URL and emitted nothing to the
attached app console. Bypass its transfer-provider layer by presenting
`UIActivityViewController` directly with the prepared URL.

## 2026-08-05: Restricted simulator compile has no runtime

`make sim-compile` can fail during asset catalog compilation when the
restricted environment cannot connect to CoreSimulator or discover an iOS
Simulator runtime. Use the host-side `make test` path for verification when
available; it successfully built and ran the unit tests in this environment.

## 2026-08-05: Generated SQLite inserts drifted from schemas

Two catalog experiments initially failed because positional `INSERT INTO ...
VALUES` placeholder counts did not match newly added table columns. For future
schema experiments, name the insert columns explicitly and validate each table's
row count immediately after generation.

## 2026-08-06: Spreadsheet authoring runtime was unavailable

The installed Spreadsheets skill's documented Node runtime could not load
`@oai/artifact-tool`. For the explicit XLSX export request, a self-contained
OOXML exporter was used as a fallback, then the workbook was successfully
converted to a native Google Sheet and verified.

## 2026-08-31: Restricted simctl connection flapped during screenshot capture

CoreSimulatorService intermittently reported an invalid connection from the
restricted shell even though other Simulator devices were booted. Opening the
macOS Simulator app and running the install, launch, and screenshot commands
with host access restored the workflow without changing or erasing devices.

## 2026-09-01: Host-side test build could not launch the simulator

The host-side `make test` path compiled and linked the app and test bundle, but
the test session could not materialize a worker because CoreSimulator was
unavailable and the attached iPhone was passcode protected. Treat the source
build as verified and report simulator test execution as unverified until a
usable simulator runtime is available.
