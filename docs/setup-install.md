# Setup and installation

## Simulator

Run `make sim-launch`. The target builds with signing disabled, boots the default
iPhone 17 Pro simulator, installs the app, and launches it.

Run `make test` for unit tests and `make lint` for Xcode static analysis.

## Physical iPhone

Connect Chase's iPhone 17 Pro, trust the Mac if prompted, and run
`make phone-deploy`. The project uses Apple Personal Team `96NAC4VTEN` and device
ID `00008150-000E41422E40401C` by default.

## Catalog refresh

`make catalog-refresh` downloads current source snapshots and rebuilds the
bundled SQLite catalog. Downloads are cached under ignored `data/downloads/`.
`make catalog` rebuilds from cached inputs and falls back to the checked-in seed
records when upstream inputs are unavailable.

