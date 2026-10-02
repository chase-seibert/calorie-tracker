# Repository guidance

Load and follow `/Users/cseibert/.codex/AGENTS.md` in addition to this file.

## Repository map

- `CalorieTracker/`: SwiftUI application source and bundled resources.
- `CalorieTrackerTests/`: unit tests.
- `scripts/`: reproducible food-catalog download and compilation tools.
- `docs/`: product, design, architecture, and setup documentation.
- `Makefile`: supported build, test, launch, deploy, and data commands.

## Commands

Prefer Makefile targets for common work. Add or update a target when a reusable
workflow is missing.

- `make sim-build`: build for iOS Simulator.
- `make sim-launch`: boot, install, and launch on the default simulator.
- `make test`: run unit tests on the default simulator. It fails immediately when CoreSimulator is unavailable.
- `make sim-compile`: compile without needing a booted simulator; use this when the simulator service is unavailable.
- `make catalog`: build the checked-in compact local catalog from source data.
- `make catalog-refresh`: download current source snapshots and rebuild the catalog.
- `make phone-deploy`: build, install, and launch on Chase's iPhone.
- `make storage-test`: run SQLite repository safety checks on the Mac, without CoreSimulator.
- `make storage-benchmark`: measure synthetic 1-, 3-, and 10-year diary histories.
- `make diary-convert INPUT=... OUTPUT=...`: explicitly convert a backed-up JSON diary; never overwrites outputs.

Before deploying the SQLite build to an existing JSON diary, follow
`docs/sqlite-storage.md`. Do not copy a live SQLite main file without its WAL
or delete the old diary as a recovery mechanism.

## StageChase task tracking

Follow [How to Work with StageChase](docs/how-to-work-with-stagechase.md) when
using the StageChase MCP for this repository's tasks.

Run `make test` with host-side execution permission. Codex's restricted
sandbox cannot connect to CoreSimulator even when the local simulator service
is healthy. Do not wait for a sandboxed test command to recover. If host-side
execution is unavailable, run `make sim-compile` and report the simulator
tests as unverified.

## Documentation index

- `docs/initial-brainstorm.md`
- `docs/product-requirements.md`
- `docs/design.md`
- `docs/architecture.md`
- `docs/setup-install.md`
- `docs/data-sources.md`
- `docs/custom-import-files.md`
- `docs/how-to-work-with-stagechase.md`
