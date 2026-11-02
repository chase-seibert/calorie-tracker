# App startup work inventory

This inventory covers cold launch through the first usable diary, plus work
scheduled by launch and the first foreground activation. Ranks use the longest
runtime an activity can reach from the current code and its dependencies. A
missing app-level deadline is reported as “no demonstrated finite bound”; it
does not mean that every run is slow. Durations are not additive because some
activities overlap.

## Ordered by worst-case runtime

| Rank | Activity and trigger | Worst-case runtime | Launch relationship |
|---:|---|---|---|
| 1 | Weekly report catch-up: eligible Sunday after 9 a.m.; also a scheduled background refresh | The selected model/provider has no app-enforced deadline; no demonstrated finite bound | Runs in a task after the initial SQLite snapshot is published. Never gates the diary. A scheduled refresh has the OS background-task deadline and cancellation handler. |
| 2 | Missed-day finalization from the durable checkpoint | Grows with the gap and affected history; no app-level duration cap | Repository transaction starts after the first snapshot. The diary first shows the existing snapshot; committed changes then refresh the UI. |
| 3 | Streak calculation over historical diary days | Grows with the number of grouped diary days; no app-level duration cap | Starts asynchronously after a snapshot and may overlap finalization. The UI displays a placeholder until a current result arrives. |
| 4 | HealthKit authorization query and queued sample reconciliation | HealthKit callbacks and system service availability have no app-enforced deadline | Authorization checks and sync are scheduled after the first usable snapshot. They are not awaited by launch. |
| 5 | SQLite open, schema migration, lock wait, and initial diary snapshot | Input/history and device I/O dependent. SQLite busy timeout is 2 seconds per busy wait; multiple statements can each wait. No total transaction bound is enforced. | This remains launch-critical because the diary cannot be shown until a valid store and its initial visible snapshot are ready. Database open runs on the detached opening task. Missing/corrupt storage fails visibly. |
| 6 | Incoming URL, share/import route, or quick-action handling | Depends on the requested import or follow-up operation; no app-level duration cap for imported data | URLs and quick actions are captured while storage opens; route work can follow once the root view is available. Keep the request pending until then. |
| 7 | Analytics upload of queued events | Request timeout is 30 seconds; retries can continue later | Starts after diary readiness or on activation. Upload never gates the diary. |
| 8 | Analytics state load and persistence | Capped at 5 MiB per state file and 1,000 queued events; local file I/O/encoding has no strict wall-clock guarantee | Service construction is cheap. State decode/pruning/persistence begins after diary readiness or the first analytics call. An oversized state file is left untouched and analytics is disabled for that process. |
| 9 | First food-catalog fingerprint and read-only SQLite open | Hashing scales with the bundled catalog size and file I/O; SQLite open has no app deadline | Catalog construction no longer reads or hashes the database. These operations are lazy and begin on first catalog use. |
| 10 | App/system setup: SwiftUI and UIKit launch, shortcut parameter update, BackgroundTasks registration, notification delegate setup, first view construction, onboarding/default reads, quick-action snapshot, and shortcut refresh | Framework and OS work has no app-controlled hard bound; app-owned reads are small | Shortcut setup and app-delegate registrations occur during launch. Remaining app-owned preference and quick-action work runs after the first usable snapshot. |
| Disabled | Legacy JSON detection, backup, decode, conversion, staging import, and publication | No runtime in the normal launch path | Automatic diary conversion is disabled. If SQLite is absent while legacy JSON exists, opening fails with a visible recovery message and leaves both files untouched. |

## What “worst case” means here

The ranks compare per-activity bounds and growth, not measured device timings.
The provider, HealthKit, operating system, disk, and large-history paths do not
have a finite runtime guarantee in app code. The 30-second analytics request
timeout bounds the configured request attempt; scheduled retries are separate
work. SQLite's busy timeout applies per wait and is not a bound on an entire
open, migration, or snapshot. No cold/warm p50, p95, or device maximum is claimed
without measurements.

## Launch milestones to measure

Use monotonic time to record process/app initialization, first frame, SQLite
open, initial snapshot, first usable diary, finalization, streak, report
catch-up, analytics state load/persist/upload, and remaining activation work.
Record workload counts (rows/days/events/bytes), never diary contents. Report
time-to-first-frame and time-to-usable-diary separately from background tail
work. Compare cold and warm launch, small and large diaries, and long-idle
histories; an observed maximum is not a worst-case guarantee.

The app emits `app.interaction_ready` once per process launch when the main
screen appears, after yielding to SwiftUI to replace the loading view. Its
`time_to_interaction_ready_ms` property measures monotonic time from the app
initializer to that point. Background work is intentionally not included.
