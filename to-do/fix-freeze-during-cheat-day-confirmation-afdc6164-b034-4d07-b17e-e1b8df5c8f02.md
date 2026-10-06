## User requirements

- As a user, I want the Yes/Undo confirmation and cheat-day control to respond promptly on every tap, so that I can mark and undo cheat days without waiting several seconds or force-quitting the app.
- As a user, I want repeated mark/undo actions to be applied once per confirmed tap and reflected in the diary, so that rapid use does not ignore clicks, queue stale actions, or leave the screen unresponsive.
- Investigate the intermittent stall across confirmation, popover dismissal, action queuing, persistence, and UI refresh before choosing a fix. The user reports that force-quitting temporarily restores responsiveness.
- Assumption: preserve current cheat-day behavior and stored data. No new feature or persistence behavior is requested.

## Architecture and data model

The current flow is `CheatDayActionPopover` → `DiaryView.confirmCheatDayAction` → serialized `DiaryStore.run` → `DiaryStore.markCheatDay`/`undoCheatDay` → SQLite-backed repository and refreshed snapshot. Correlated, bounded diagnostics already record confirmation, popover lifecycle, action queue/wait, storage mutation, refresh, state publication, and failures under an operation ID. Use these timings to localize the stall; add narrowly scoped input or rendering measurements only if existing events cannot explain an unresponsive tap.

No material architecture, data-model, schema, or migration change is expected. Keep diagnosis and any fix within the existing SwiftUI diary action and store path unless evidence identifies another cause. Do not change cheat-day adjustment, food-retention, or undo semantics.

## Basic test cases

- From a representative fixture, mark then undo the selected day repeatedly (including about 20 alternating cycles); each confirmation should respond promptly, update the control/banner and diary state, and leave the control usable for the next cycle.
- Tap Yes rapidly more than once while one confirmation is visible. The action should not apply twice, become stuck, or leave the popover/UI in a state that requires relaunch; verify the intended single-action behavior.
- Repeat from each existing cheat-day entry point (diary toolbar and any visible banner/logging affordances). Confirm popover appearance and dismissal stay responsive and the selected date is the one changed.
- Exercise both a normal diary and the date-relative simulator fixture. If the stall does not reproduce with the fixture, repeat against a standalone SQLite export of the phone diary imported with the documented fixture workflow; compare operation-correlated timings without exposing diary contents.
- Verify persistence after app relaunch and confirm a failed save reports the existing error path while the interface recovers for another action.

## High-level implementation details

1. Reproduce with repeated mark/undo cycles on the date-relative simulator fixture and, when needed, a standalone phone database export. Capture the existing `diary-performance.jsonl` events for each operation ID; distinguish missed input, popover dismissal delay, action-queue wait, database/refresh work, and delayed SwiftUI rendering. Do not infer that SQLite is responsible from the symptom alone.
2. If evidence does not identify the delay, add minimal diagnostics or a focused UI stress test that records attempted/accepted confirmations and checks repeated state transitions. Keep instrumentation bounded and free of diary content.
3. Fix the localized cause while preserving serialized writes, current confirmation semantics, and cheat-day data behavior. Avoid broad persistence redesign unless measurements show it is necessary.
4. Add regression coverage for repeated mark/undo, duplicate confirmation taps, UI recovery after errors, and persistence/relaunch as applicable to the diagnosed layer. Verify with the focused test, repository test/build workflow, and physical-phone deployment when implementation is requested; determine phone acceptance by checking that the app launches and the reproduction loop remains responsive.

Risks: a stress run may miss an intermittent timing window, and the bundled fixture may not match the phone diary's size or state. If phone-state comparison is needed, use a standalone, consistent SQLite export via `make sim-import-fixture` as documented; do not copy only a live database file or mix SQLite WAL sidecars. The root cause and whether additional instrumentation is needed remain unresolved until reproduction evidence is collected.
