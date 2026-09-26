# On-device storage and SQLite cutover

## Implemented boundary

The app, Siri intents, and widgets now use the same `DiaryRepository` and
`DiaryEngine`. No new package, Core Data stack, or SwiftData dependency is
required; both targets link Apple's system SQLite library.

| State | Storage | Rationale |
| --- | --- | --- |
| Logged foods, meals, ingredient snapshots, calorie adjustments | Shared `Diary.sqlite` | Unbounded history, indexed dates, transactional edits |
| Personal foods, reusable meals and ingredients | Same database | Stable identities; deleting a template must not delete history |
| Favorites, combined favorite ordering, per-food quantities, renamed foods | Same database | Changed transactionally with diary/library operations |
| Goal, tracking start, day statuses, alcohol aggregates | Same database | Consistent diary/report/HealthKit rules |
| Quick-log receipt | Same database | Committed in the same transaction as the log |
| Pending HealthKit days and known/deleted sample identities | Same database | Survives process death and disconnected Health permissions |
| Focus toggles, onboarding completion, debug controls | UserDefaults | Small independent preferences |
| Last grams/ounces preference | Shared UserDefaults, with app preference fallback | Small preference needed by app and extensions |
| Food catalog | Existing bundled read-only SQLite database | Immutable catalog remains separate from private user data |
| Analytics queue, delivery state, diagnostic history | Existing app-private JSON | Separate follow-up; deliberately not shared with widgets |
| Share/export files, input documents | Files | Artifacts, not the authoritative diary |
| Apple Health samples | HealthKit | External projection, never the authoritative diary |

Analytics has its own bounded retention and single-process owner. A later
`Analytics.sqlite` can move its queue/batches/diagnostics into rows without
coupling telemetry failures to diary commits. This implementation does not
change analytics delivery, configuration, consent, or retention behavior.

## Repository design

`Diary.sqlite` lives under `CalorieTracker/` in App Group
`group.com.cseibert.CalorieTracker`. The database uses WAL, foreign keys,
`synchronous=FULL`, a two-second busy timeout, and one serial executor per
connection. A process-local executor does not coordinate other processes;
SQLite transactions do that. Every mutation rereads its affected rows inside
`BEGIN IMMEDIATE`, applies domain rules, writes the differences, and commits.
It never saves the app's potentially stale presentation cache over the store.

Entries and ingredient lists have separate rows. Frequently queried dates,
IDs, nutrient totals, meat flags, and ordering are columns. Extensible food and
quantity snapshots remain JSON *inside individual rows*. There is no diary-size
JSON blob. Entry-to-template links are intentionally soft; only owned ingredient
rows cascade when their parent entry or template is deleted. Nullable Fiber,
ingredient order, original UUIDs, and detached meal snapshots are preserved.
New meal logs store explicit category overrides separately from derived flags.

Food resolution adds optional provenance inside those existing food payloads;
it needs no SQL schema change. Imports commit library snapshots and diary rows in
one transaction. Reviewed historical corrections use indexed food scopes after a
verified SQLite backup, not a stale full-document save. Approve All uses one backup
and one transaction for the reviewed batch; any stale suggestion aborts the batch.
See
[Food classification resolution](food-resolution.md). Conversion remains lossless.

`DiaryStore` is a main-actor presentation facade. Opening, saving, and loading
run off the main thread. Its entry cache contains 90 days, the selected diary
day, and the newest 30 distinct Recent items. Historical search queries the
database rather than only this cache. Full-history streaks aggregate in SQL.
Some small library/status collections remain fully loaded; this is not a claim
that every query is constant time. Explicit goal recalculation and conversion
are allowed to process all history.

Views wait for commits before dismissing edit forms or reporting success.
Load/save failures are visible; a failed initial load cannot expose an empty
writable diary. Unsupported schemas and non-SQLite files are rejected, not
replaced. Schema changes after this cutover must use numbered transactional
migrations; the initial schema is `PRAGMA user_version = 1`.

HealthKit work is a durable, revisioned day queue. Each diary transaction retains
known sample identities, including deleted entries, and marks affected days.
The foreground app drains pending days after authorization. Acknowledgement
only removes the revision actually synchronized; a concurrent widget change
keeps newer work pending. Failed work remains queued for the next attempt.
Normal app activation does not enqueue all historical entries. Settings' manual
sync deliberately requests a full reconciliation. HealthKit is not part of a
SQLite transaction, so synchronization is retryable and eventually consistent.

The database directory and SQLite files use protection until first device
unlock. Widgets may be unavailable before that unlock. Do not change the
protection of unrelated files in the App Group.

## One-time on-device migration for the owner's phone

The owner chose an on-device cutover after CoreDevice's shared-container file
transfer failed. **Install the update without uninstalling the existing app.**
On first foreground launch, if SQLite is absent, `DiaryJSONMigration`:

1. Selects the shared `CalorieTracker/Diary.json` first. The older app-private
   JSON is used only if the shared file is absent, not if it is unreadable or
   invalid. Missing App Group access fails closed.
2. Writes and verifies a byte-identical backup in the app-private
   `Library/Application Support/CalorieTracker/SQLiteMigrationBackups/<UUID>/Diary.json`.
   It leaves both original JSON locations untouched. Backup directories are
   private; files use mode 0600 and protection until first unlock.
3. Decodes and validates the JSON, imports into a unique staging database on
   the destination volume, runs integrity/foreign-key checks, and compares every
   decoded record against the source. It does not enrich metadata, change IDs,
   rebase dates, or finalize days during conversion.
4. Produces a standalone SQLite backup, verifies it again, changes the private
   candidate to DELETE journaling, and closes it so no WAL/journal is required.
   An unused SHM index can remain in staging; it is never published.
   `VerifiedConversion.json` next to the JSON backup records SHA-256 checksums,
   collection counts, and the successful round-trip check. This verifies the
   pre-launch snapshot, not subsequent app edits or HealthKit synchronization.
5. Rechecks that the source JSON has not changed, then atomically publishes
   `CalorieTracker/Diary.sqlite` using a same-volume hard link that cannot
   overwrite an existing destination. The temporary link is then removed.
   Opening the normal repository re-enables WAL.

Only the foreground app migrates. Widgets/Siri refuse to create a missing live
database and ask the owner to open the app first. Later launches skip conversion
when SQLite exists; corrupt or unsupported SQLite is never replaced from old
JSON. Backup, decode, or verification failure leaves no published database and
surfaces a load error. A crash before publication leaves the originals and any
backup intact; retry uses a new staging/backup directory. A crash after
publication leaves a complete verified SQLite file.

Phone checklist:

1. Stop edits and widget/Siri logging, close the old app, and keep the phone
   unlocked for installation. Preserve the old signed build; use a separate
   `DERIVED_DATA` directory when building the update.
2. Install without uninstalling; open the app and allow conversion to finish.
3. Retrieve the private migration backup and manifest when device-copy access
   permits. Verify today and an older day, entry/ingredient counts, favorites,
   saved/one-off meals, alcohol, statuses, nullable Fiber, and meat flags.
   Older classifications can have ambiguous override provenance; conversion
   preserves the stored record rather than silently reclassifying it.
4. Verify relaunch, normal logging, charts, widgets/Siri, and HealthKit on the
   phone. Do not infer successful cutover merely because the app opens.
5. Keep the backup. An old-app rollback uses old JSON and omits post-cutover
   logs; reconcile those before rolling back. Never delete SQLite to recover
   from a load error. On-device copies do not protect against uninstalling the
   app or losing the phone, so retain an off-device backup when possible.

The standalone developer converter remains available for rehearsal or a manual
cutover, and refuses to overwrite output files:

```sh
make diary-convert INPUT=/private/path/Diary.json OUTPUT=/private/path/Diary.sqlite
make diary-validate INPUT=/private/path/Diary.sqlite
```

For future backups of a live SQLite store, use `DiaryRepository.backup(to:)`.
Copying only `Diary.sqlite` while it is open can omit committed changes in
`Diary.sqlite-wal`. Never mix a main file and sidecars from different snapshots.

## Developer Diagnostics database transfer

Debug builds expose **Settings → Developer Diagnostics → SQLite Database** with
standalone export and import actions. Export uses `DiaryRepository.backup(to:)`,
SQLite's online backup API, so committed changes in the live WAL are included;
it does not serialize the diary into a second row-oriented format. The resulting
`.sqlite` file can be moved from the phone through Files, AirDrop, or another
file-transfer method and then imported into the simulator.

Import accepts only a standalone export, not a live database accompanied by
`-wal`, `-shm`, or `-journal` sidecars. It validates the incoming database,
creates and validates a `BeforeImport-<UUID>.sqlite` backup of the current
database, closes the live connection, replaces the database, and reloads the
store. Existing sidecars are archived rather than mixed with the imported file.
The pre-import backup remains in the app's `SQLiteTransfers` directory for
recovery and appears under **Previous Backups**. Selecting one restores that
snapshot using the same validated replacement flow, creating another backup
of the current database first. The app retains the eight newest import backups
for up to 30 days and prunes older snapshots.

For the desktop simulator path, use
`make sim-import-fixture INPUT=/private/path/YumChase-Database.sqlite`. The
target validates the standalone file, copies it into a new UUID-named App Group
fixture, selects it for the Debug simulator, and launches the app. It does not
overwrite the simulator's normal diary or the checked-in fixture. The transfer
contains the private diary database only; it does not include the bundled food
catalog, UserDefaults preferences, analytics files, or HealthKit data.

## Verification and scale

```sh
make storage-test       # Mac, no simulator required
make storage-benchmark  # Synthetic 1-, 3-, and 10-year histories
make test               # Simulator unit tests; host access required
make ui-test-reorder    # Real drag + persisted order after relaunch
make ui-test-fixture    # Date-relative fixture launch
```

The storage checks also cover on-device conversion, exact JSON backup bytes,
shared-source priority, idempotent relaunch, invalid/newer JSON refusal, backup
failure, and retry safety. They cover library/ordering round trips, nullable Fiber and
ingredient classification, detached snapshots, template deletion, concurrent
connections, rollback, revision-checked HealthKit acknowledgements, deletion
tombstones, WAL-aware backup, corrupt/future-schema refusal, quick-log receipts,
and historical search. The UI facade also has asynchronous loading and corrupt
file tests. The SQL streak parity test covers travel between time zones,
mixed known/unknown ingredient Fiber, and the tracking-start boundary.

Verified locally after adding on-device conversion: 83 unit tests, the standalone
storage self-tests (including migration), and a signed physical-device build.
The earlier refactor also passed the drag/relaunch UI test, date-relative fixture
flow, and Release simulator build. A conversion rehearsal preserved the checked-in
fixture's 24 entries and 6 meals. Physical-phone conversion and HealthKit checks
remain separate from these local tests.

Illustrative Mac measurements from September 1, 2026, using 15 entries/day:

| History | Entry count | 90-day read | Log transaction | Full streak query |
| --- | ---: | ---: | ---: | ---: |
| 1 year | 5,475 | 25 ms | 2 ms | 10 ms |
| 3 years | 16,425 | 67 ms | 1 ms | 41 ms |
| 10 years | 54,750 | 194 ms | 2 ms | 188 ms |

Each read decoded 1,350 entries rather than the full history. These are
single-run developer-machine timings, not phone latency guarantees or a formal
benchmark. Imports took approximately 0.4, 1.2, and 4.2 seconds respectively.
The physical-device cutover should include timing first launch, logging, trends,
and a long streak before calling performance validated on the phone.

Simulator fixtures now rotate to isolated UUID-named databases under
`CalorieTracker/Fixtures/`; they never unlink the normal diary or a live WAL.
The selected simulator fixture is shared with its widget. Fixture routing is
compiled out on physical devices and Release builds. Old simulator fixtures can
be removed by resetting the simulator's app data when no process is using it.
