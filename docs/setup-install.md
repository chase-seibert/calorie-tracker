# Setup and installation

## Simulator

Run `make sim-launch`. The target builds with signing disabled, boots the default
iPhone 17 Pro simulator, installs the app, and launches it.

Run `make test` for unit tests and `make lint` for Xcode static analysis. Run
`make ui-test-reorder` for the focused simulator test that performs an actual
long-press row drag and verifies the new order survives an app relaunch.
The UI-test target is isolated in its own shared Xcode scheme, so normal builds
and `make test` do not build or run it. Use this slower test for changes to the
logged-food list, drag/drop, swipe deletion, or diary ordering; do not add it to
the routine build or unit-test workflow.

## Physical iPhone

Connect Chase's iPhone 17 Pro, trust the Mac if prompted, and run
`make phone-deploy`. The project uses Apple Personal Team `96NAC4VTEN` and device
ID `00008150-000E41422E40401C` by default.

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
