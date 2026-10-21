# Setup and installation

## Existing phone diary: one-time SQLite conversion

Install the update without uninstalling the old app. On first foreground launch,
the app preserves the original JSON, creates a byte-verified private backup,
and publishes SQLite only after full record and integrity verification. Failures
stop with an error, never an empty writable diary. Follow the phone checklist in
[`sqlite-storage.md`](sqlite-storage.md); retain the old build by using a separate
`DERIVED_DATA` directory for this update. `make diary-convert` remains available
for manual conversion; `make storage-test` includes on-device conversion checks.

## Simulator

Run `make sim-launch`. The target boots the default iPhone 17 Pro simulator,
installs the app, and launches it. The runtime build is ad-hoc signed so the app
and widget receive their shared App Group entitlement;
`make sim-compile` remains the signing-disabled compile-only path.
Debug simulator runs load and reset the date-relative device fixture by default,
including manual launches from Xcode. The fixture always supplies diary entries
for yesterday, today, and tomorrow plus unobstructed repeated sets for every
Magic time band. It is written to the shared App Group container so the widget,
Siri intents, and icon quick actions exercise the same fixture.
Set `CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE=1` in the scheme environment when
you explicitly need an empty, persistent simulator diary.

## OpenAI meal-photo analysis

This private-app integration requires an OpenAI API key entered by the owner in
**Settings → Connections → OpenAI API**. The key remains in this device's
non-synchronizing Keychain and is never bundled with the app. A ChatGPT app
subscription does not provide API access; API usage is billed separately by
OpenAI. Review current model and image-token rates at the
[OpenAI API pricing page](https://developers.openai.com/api/docs/pricing). At
implementation time, `gpt-6-luna` is listed at $0.10 per million input text
tokens and $0.50 per million output text tokens; image input is billed by image
tokens separately. The current implementation selects `gpt-6-luna` for image
input and strict structured output. Model availability and rates can change.

The app sends one foreground request to the Responses API only after the user
chooses Analyze Photo. A retry is a new billable request. This direct
client-key design is for private deployment; use an authenticated backend before
distributing the app to other users.

## Weekly food reports

Open **Settings → Reports** to edit the report prompt, choose OpenAI or Apple's
on-device Foundation Model, enable Sunday background refresh, and open the
latest report. Manual generation can replace the report even when this week's
version is already saved; automatic generation reuses that version. Local-model
availability requires a supported Apple Intelligence device running iOS 26 or
later. The local route keeps the diary summary, food names, and prompt on the
device and does not use the OpenAI API key. The latest completed seven days
remain the primary report week; two preceding completed weeks provide trend
context. Generation runs only when food or meal entries appear on at least
three distinct days in the latest week. The summary compares calories, protein,
known fiber, explicitly marked cheat-day and gap-day frequency, and the calorie
overage on each marked cheat day. It also highlights single foods by calories,
fiber, and protein across the three-week window. Fiber quantities are rounded
to at most two decimal places. Empty unmarked days are not counted as gaps, and
unknown nutrient values remain unknown. Enabled guidance follows Trends: up to 2 drinks per
day, 0 processed-meat servings per week, and 14 g of fiber per 1,000 calories.
HealthKit data and diary notes are excluded. Debug builds use the same
Keychain API key configured in **Settings → Connections → OpenAI API**; each
successful request may incur OpenAI API charges. Do not use a client API key as
the access control for a paid distributed product. Release requests stay
disabled until the authenticated, paid backend is implemented.

Background refresh is scheduled for Sunday morning in the current time zone,
but iOS controls when or whether the task runs. The app may generate late or
skip a week if the system does not grant runtime. Notification permission is
requested when automatic reports are enabled; the notification is submitted
only after the report is saved. You can also create a report on demand from the
Debug-only **Settings → Developer → Developer Diagnostics** action.

To use a standalone SQLite export from the phone as the simulator's diary,
run:

```sh
make sim-import-fixture INPUT=/private/path/YumChase-Database.sqlite
```

The target validates the file, installs the Debug app, copies the database into
a new isolated App Group fixture, selects that fixture, and launches the app.
It leaves the normal simulator diary untouched. Re-running `make sim-launch`
with its default fixture settings will select and reset the generated demo
fixture again, so use `make sim-import-fixture` whenever you want to switch
back to an exported phone snapshot.

Run `make test` for unit tests and `make lint` for Xcode static analysis. `make
test` requires CoreSimulator and the configured simulator to be available; it
now reports that prerequisite immediately instead of waiting for Xcode's
destination discovery. When CoreSimulator is unavailable, use `make
sim-compile` for a simulator-independent source compile check. Run
`make ui-test-reorder` for the focused simulator test that performs an actual
long-press row drag and verifies the new order survives an app relaunch.
The UI-test target is isolated in its own shared Xcode scheme, so normal builds
and `make test` do not build or run it. Use this slower test for changes to the
logged-food list, drag/drop, swipe deletion, or diary ordering; do not add it to
the routine build or unit-test workflow.

To exercise first-time onboarding in a DEBUG build, open Settings → Developer
Diagnostics → Reset First-Time Onboarding. The reset restores every optional
focus area to its enabled default and presents the onboarding immediately.

## Analytics configuration

Copy `Config/AnalyticsConfig.example.plist` to the git-ignored
`Config/AnalyticsConfig.local.plist` and replace the placeholder endpoint and
secret with the namespace-scoped values. The Xcode target copies that local file
into the app bundle as `AnalyticsConfig.plist` when it exists. If it is absent or
invalid, analytics remains disabled and the rest of the app is unchanged.

Debug builds default to the `debug` audience and Release builds default to
`production`; set an explicit `audience` in the plist only for a beta or test
deployment. CI should generate the local plist from its secret store without
printing the secret. Never commit the local plist. Debug builds expose queue and
per-event delivery state under Settings → Developer Diagnostics → Analytics
Events. Selecting an event displays its payload, including search strings or
barcodes when present. Request headers, signatures, and the signing secret are
never displayed.

## Physical iPhone

Connect Chase's iPhone 17 Pro, trust the Mac if prompted, and run
`make phone-deploy`. The project uses Apple Personal Team `96NAC4VTEN` and device
ID `00008150-000E41422E40401C` by default.

The app and widget targets both require the App Groups capability with
`group.com.cseibert.CalorieTracker`. Automatic signing should create or update
the app and widget provisioning profiles. After installing, launch Yum Chase
once so it can migrate an existing diary and publish its Siri shortcuts and
dynamic icon actions. Add “Yum Chase Quick Log” or “Yum Chase Calories Left”
from the Home or Lock Screen widget gallery. See `docs/quick-entry.md` for
supported Siri phrases and system behavior.

If device signing reports `No Accounts` or says that a provisioning profile
does not support the App Group, sign back into the development team in Xcode →
Settings → Accounts. Then open Signing & Capabilities for both the
`CalorieTracker` and `VitaChaseWidgets` targets and let automatic signing
regenerate their profiles. The same App Group must be enabled for both bundle
identifiers.

On the first launch, open Settings in Yum Chase and choose Connect Apple
Health. Grant write access for calories, carbohydrates, fat, protein, and Fiber
when prompted. HealthKit is unavailable in the simulator, so the connection
flow must be exercised on the iPhone.

For normal development without a cable, pair the iPhone once in Xcode: open
Manage Devices from the run-destination menu and select the iPhone as the build
destination. Disconnect the cable, leave the Mac and unlocked iPhone on the same
network, then run `make phone-wifi-deploy`. The target checks that Xcode can see
the paired phone before reusing the standard signed build, install, and launch
workflow. Increase its wait when needed with, for example,
`make phone-wifi-deploy PHONE_DESTINATION_TIMEOUT=120`.

## Catalog refresh

`make catalog-refresh` downloads current source snapshots and rebuilds the
bundled SQLite catalog. Downloads are cached under ignored `data/downloads/`.
`make catalog` rebuilds from cached inputs and falls back to the checked-in seed
records when upstream inputs are unavailable.
