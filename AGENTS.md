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

When a Codex-sandboxed simulator command reports that CoreSimulator is
unavailable, do not wait for it to recover: retry the command with host-side
execution permission. If that is unavailable, run `make sim-compile` and
report the simulator tests as unverified.

## Documentation index

- `docs/initial-brainstorm.md`
- `docs/product-requirements.md`
- `docs/design.md`
- `docs/architecture.md`
- `docs/setup-install.md`
- `docs/data-sources.md`
