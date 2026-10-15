# Task #196 verification — October 14, 2026

Every food source and meal context now uses the actual `CustomizationScreen`
layout: pinned name/source and macro summary, bounded scrolling content, shared
quantity controls, and one pinned contextual primary action. USDA/OFF/custom
foods have real portions and added-food drafts; Chase foods retain their option
pills. Meals expose counts and the same ingredient cards. Search and suggestion
lists use explicit, namespaced detail buttons with independent shortcuts.

[Complete screenshot index](unified-ui/index.md) ·
[Side-by-side comparison](unified-ui/comparison.html) ·
[Capture manifest and SHA-256 checksums](unified-ui/capture-manifest.json)

The 21 unaltered PNGs cover all nine requested food/meal types, four restored
logged edits, scrolling, a unit menu, and parent/child review. They were visually
inspected for shared header/footer placement, readable names and serving labels,
contextual actions, classification labels, and consistent ingredient cards.
Stored import/photo definitions use the production review views without an AI
request. The earlier two screenshots in this directory document the previous
implementation, not the new unified UI.

## Checks

- Host simulator and signed physical-device builds succeeded.
- `make ui-test-food-detail TEST_DIAGNOSTICS=never`: **4/4 passed**. Coverage
  includes real mixed-source search/badge taps; all screenshot routes; plain
  historical USDA/OFF edits without rebuild warnings; mass-preserving unit
  changes; nested/parent Cancel; quantity Save and relaunch; entry count/order;
  mixed-source meal composition; and exactly one quick-add without opening detail.
- `make test TEST_DIAGNOSTICS=never`: **145/147 passed**, including all seven
  task-specific persistence/calculation tests. The same two catalog tests also
  failed in the earlier untouched-HEAD baseline: burger included constituents
  and the old v2 search-evaluation fingerprint (`6f988a00804f` versus the bundled
  catalog's `f51cd7e8639b`). No catalog data was changed by this implementation.
- `make storage-test`: all safety checks passed: concurrent writers, rollback,
  WAL-aware backup, migrations, corrupt/future-store refusal, identities,
  ordering, snapshots, nullable fiber and classifications.
- `make ui-test-reorder TEST_DIAGNOSTICS=never`: passed, including persisted order
  after relaunch.
- `make ui-test-cheat-day TEST_DIAGNOSTICS=never`: edge-tap check passed. The
  repeated confirmation stress test still failed when a logged-row tap did not
  produce confirmation. This test also failed in the earlier untouched-HEAD
  baseline; it is not reported as passing.
- `git diff --check`: passed.

Final result bundles under `build/Logs/Test/`:

- `Test-CalorieTrackerUITests-2026.10.14_14-15-17--0700.xcresult` — 4 shared UI tests and final captures.
- `Test-CalorieTracker-2026.10.14_14-09-57--0700.xcresult` — 147 unit tests.
- `Test-CalorieTrackerUITests-2026.10.14_14-10-08--0700.xcresult` — reorder.
- `Test-CalorieTrackerUITests-2026.10.14_14-20-43--0700.xcresult` — cheat-day checks.

Re-export the exact matrix with:

```sh
make export-food-detail-evidence RESULT_BUNDLE=build/Logs/Test/Test-CalorieTrackerUITests-2026.10.14_14-15-17--0700.xcresult
```

## Phone and handoff

`make phone-deploy DERIVED_DATA=build/task196-phone` built and installed the final
production UI over the existing app without uninstalling it. Launch was denied
by `FBSOpenApplicationErrorDomain` code 7, `Locked`. A later `make phone-launch`
retry could not obtain the required CoreDevice services (error 4016). An earlier
unified build launched successfully, but final-build interaction and HealthKit
delivery on the phone remain unverified. No SQL schema migration was needed.

Four representative screenshots were attached to StageChase and retrieved for
integrity verification; their server SHA-256 values match the local PNGs. Task
completion stays user-controlled. The run was recorded, but StageChase rejected
the current thread link with “already has an active writer”; this run still needs
to be linked from task detail.

Full VoiceOver navigation, maximum accessibility text sizes and live file-picker/
AI-analysis round trips were not retested. The stored review contexts, existing
validation and accessible Button semantics are covered by the checks above.
