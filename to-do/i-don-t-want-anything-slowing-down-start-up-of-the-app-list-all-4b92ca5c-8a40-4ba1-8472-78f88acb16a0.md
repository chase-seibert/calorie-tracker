# Startup work inventory and responsiveness plan

## User requirements

- As a user, I want to see and use the diary as soon as its required SQLite data is ready, so that optional startup work does not make the app feel slow.
- As a user, I want every activity that can run during launch identified and ranked by worst-case runtime, so that the longest delays can be removed from the launch-critical path first.
- As a user, I want weekly report generation, missed-day finalization, and current-streak calculation to run asynchronously after the diary appears, so that none of them delays startup.
- As the sole current installer, I want legacy JSON migration disabled because my diary is already migrated, so that launch never checks, backs up, decodes, or imports that legacy diary.
- As a user, I want analytics state initialization to be fast and uploads to remain in the background, so that telemetry cannot hold up the diary.
- Scope assumption: include cold launch, first usable diary, and work scheduled immediately on activation. Treat system-managed and provider-dependent work as potentially unbounded unless the app imposes and verifies a bound. Preserve diary integrity and never silently substitute an empty writable diary for an unavailable existing store.

## Architecture and data model

No material diary data-model or schema change is required. Keep `DiaryRepository` as the authority and `DiaryStore` as its presentation cache. Make initial readiness depend on opening the existing SQLite store and publishing its required snapshot, or showing a visible storage error. After that, schedule missed-day finalization, current-streak calculation, report catch-up, and analytics work asynchronously. Serialize writes through the repository, keep finalization transactional and checkpoint only committed work, and use generation checks so late results cannot overwrite newer state. Disable the legacy JSON migration path: do not decode, back up, import, or publish legacy JSON. If SQLite is missing while a legacy file is present, fail visibly without modifying either file or creating an empty writable diary. No migration or analytics schema change is needed.

## Basic test cases

- On a normal launch with SQLite present, the diary becomes usable after storage open and initial snapshot; missed-day finalization, streak calculation, report generation, and analytics do not hold the launch screen.
- With SQLite missing and legacy JSON present, launch does not read, copy, decode, convert, or delete the JSON; it shows a clear storage-unavailable/recovery error and does not create an empty writable diary.
- With SQLite missing and no legacy JSON, verify new-store behavior is explicit and cannot overwrite an existing file.
- On Sunday after the scheduled report time, with automatic reports enabled and a slow, unavailable, or failing model/provider, the diary appears first; catch-up runs later and remains retryable, with failure visible in the report surface.
- With missed days to finalize, the diary appears from the current SQLite snapshot first, then finalized statuses/checkpoint are committed transactionally and the UI refreshes. A crash/relaunch retries safely without losing or double-applying changes.
- While an async streak query is running, the diary remains usable with a loading/placeholder streak; the result appears when ready, and a result from an older refresh is discarded.
- With queued analytics and no network, launch remains usable; upload may reach its configured 30-second request timeout without delaying diary presentation.
- With large analytics state, service startup stays bounded and does not synchronously decode/encode an unbounded payload; queued events are retained and later uploads remain retryable.
- With a large diary and a long gap since finalization, measurements identify snapshot, finalization, and streak costs separately; no entries or history are lost or silently omitted.
- With corrupt, unsupported, locked, or unavailable storage, the existing visible retry/error behavior remains and an empty writable diary is never substituted.
- Verify cold launch, warm activation/reload, incoming import/deep-link handling, and quick-action launch separately so their work is not conflated.

## High-level implementation details

1. Instrument cold-launch milestones with monotonic timestamps and one launch ID: process/app initialization, first frame, SQLite open, initial diary snapshot, first usable diary, finalization, streak, optional report work, analytics state load/persist/upload, and remaining activation work. Record elapsed time and workload counts without diary contents. Distinguish time-to-first-frame, time-to-usable-diary, and background tail work. Since migration is disabled, do not invoke its backup/decode/import path.
2. Build and maintain the requested startup inventory, ordered by worst-case class. Current code-based ranking (validate with measurements; label data-dependent/provider work as having no demonstrated finite app-level bound):

   | Rank | Activity and trigger | Worst-case runtime basis | Current launch impact / plan |
   |---|---|---|---|
   | 1 | Weekly report catch-up on eligible Sundays after 9 a.m. | Model/provider work has no demonstrated app-level deadline; potentially unbounded | Currently awaited before `hasPreparedLaunch`; move after diary presentation and run independently |
   | 2 | Missed-day finalization since the durable checkpoint | Grows with elapsed days and records in the range; no app-level duration cap | Currently awaited before snapshot; run transactionally in background, then refresh the UI |
   | 3 | Current-streak calculation | Aggregates historical diary days; work grows with history and has no demonstrated app-level cap | Currently awaited as part of reload; compute after initial snapshot and publish asynchronously |
   | 4 | Analytics upload of queued events | Configured URL request timeout is 30 seconds; retries are scheduled separately | Already launched in a task; preserve background delivery and never await it during launch |
   | 5 | SQLite open, schema/settings migration, transaction, and lock wait | Typically small; busy timeout is 2 seconds per busy wait; total may include multiple operations | Required for diary snapshot; keep only essential open/validation on the launch path |
   | 6 | Required diary snapshot | Scoped to the cache window plus selected day/recent items; cost depends on stored rows and device I/O | Await only enough to publish a useful diary; do not include streak or finalization |
   | 7 | Catalog fingerprint and read-only SQLite open | SHA-256 work scales with bundled catalog size and storage speed | `CatalogStore` is created during `App.init`; measure and avoid repeated fingerprinting |
   | 8 | Analytics configuration/state load, pruning, batch preparation, and persistence | Depends on file size and retained queue; give it explicit byte/event bounds | Currently loaded in service initialization and persisted by `start()`; defer/lazily load after first usable diary |
   | 9 | HealthKit availability/authorization checks and queued sync | Authorization checks are local system calls; HealthKit operations depend on system response | Keep synchronization asynchronous and unawaited |
   | 10 | Shortcut parameters, quick-action snapshot, background-task registration/scheduling, onboarding/default reads | Expected work is small; system APIs have no app-controlled hard bound | Split across initialization, delegate launch, and post-load callbacks; retain pending actions/routes |
   | Disabled | Legacy JSON detection/conversion, backup, decode, staging import, and publication | No launch runtime when disabled | Remove from the active launch path. If SQLite is absent but legacy JSON exists, fail closed without importing or modifying it |

3. In `CalorieTracker/Data/DiaryStore.swift` and `CalorieTracker/Data/DiaryRepository.swift`, separate initial SQLite snapshot from `prepare` and streak. Publish the snapshot and mark the diary usable, then start finalization and streak work without awaiting either. Keep finalization serialized and transactional; checkpoint only committed work, then reload affected diary values. Compute streak in its own async request, show an interim state, and use refresh generations to ignore stale completions. Ensure a user edit or quick action cannot be overwritten by a background refresh.
4. In `CalorieTracker/App/CalorieTrackerApp.swift` and `CalorieTracker/Data/WeeklyFoodReport.swift`, reveal the usable root as soon as the initial snapshot is ready. Schedule catch-up independently after presentation, deduplicate concurrent launches/activations, preserve background scheduling/retry behavior, and surface report status/errors outside the launch gate.
5. In `CalorieTracker/Data/DiaryRepository.swift`, disable/remove legacy JSON detection and conversion from the normal open path. A missing SQLite file with legacy JSON present must fail visibly rather than create a blank store; leave the original JSON untouched. The user confirms the only installed phone already completed migration.
6. In `CalorieTracker/Data/AnalyticsService.swift`, keep upload off the launch path and make initialization cheap: defer reading/decoding persisted analytics state until after the first usable diary, enforce byte/event bounds, prune incrementally, and move batch encoding/compression/signing and disk persistence off the main actor where needed. Preserve atomic durable queue semantics so deferral, termination, or network failure does not drop events. Verify initialization stays fast and never waits for upload.
7. Confirm actual call ordering and blocking boundaries in the app entry point, app delegate/quick actions, diary store/repository, catalog, weekly report, analytics, and HealthKit code. Update the inventory if tracing finds other synchronous initialization, view `.task` work, or activation-triggered reloads. Avoid repeatedly hashing/reading the full catalog or doing expensive synchronous I/O on the main actor.
8. Compare cold and warm launches on small/large diaries and long-idle histories. Report observed p50/p95/max and workload size per phase; an observed maximum is not a worst-case guarantee. Verify report delay/failure, missed-day retries, stale streak results, analytics durability/offline behavior, disabled migration failure handling, deep links, quick actions, and data preservation. For an eventual implementation, run repository simulator and phone deployment workflows and report blockers precisely.

Material risks: while finalization and streak are pending, label provisional values clearly and refresh after committed work; serialize writes to avoid stale snapshots replacing new entries. Disabling migration means a device with only the old JSON diary cannot open it automatically, so show a clear non-destructive error. Preserve pending deep links/imports and quick actions during initial loading. Set the target time-to-first-usable-diary from measurements rather than guessing.
