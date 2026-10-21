## User requirements

- As a user, I want to long-press a logged food item and choose **Duplicate Today**, so that I can quickly log the same item again today with its existing quantity and configuration.
- As a user, I want the duplicate to appear as a separate entry in today's diary, so that I can change or remove it without changing the source entry.
- As a user, I want to select multiple logged foods or meals and choose **Duplicate Today**, so that I can repeat a group of diary entries together.
- The action includes logged food and meal rows; alcohol and calorie-adjustment rows are excluded. The source may be on another diary date, and the destination is the device's current calendar day, regardless of the selected diary date.

## Architecture and data model

No material schema or persistence-model change is expected. `DiaryEntry` already captures the food, quantity/unit/portion, nutrients, and optional meal/configuration snapshots. Add a domain operation that copies an eligible entry into today's date with a fresh entry identity, current log timestamp, and display order, preserving the source's logged values and snapshots. Ensure nested meal-item identities are safe for independent editing if meal duplication is included.

Route the operation through `DiaryStore` and `DiaryEngine` so single and multi-entry copies use one transactional write that loads all selected source IDs and the destination day's rows. Validate the full selection before appending any copy, preserve source display order, and refresh through normal store publication. If today's logging is blocked by a cheat day, take the user to today and present the existing cheat-day action. Do not mutate or delete sources. No catalog, SQLite schema, migration, or export-format change is needed.

## Basic test cases

- Long-press an eligible row and select **Duplicate Today**: one new row appears on today's date with the same food, quantity, unit, portion, nutrition, and configured components; its ID is new and the original row is unchanged.
- Duplicate a row from a past selected date: the copy is added to the actual current day, not the selected historical day.
- Duplicate a row while viewing today: a second independent row is added with a new identity and correct ordering/totals.
- Select two or more rows and choose **Duplicate Today**: every selected row is copied once in source display order; no copy is made for an empty selection.
- If a batch contains a row that is no longer available or is ineligible, no partial copies are written.
- Exercise long-press reorder and trailing swipe delete after adding the action: reorder still moves rows and delete retains its existing confirmation/behavior.
- Attempt the action on an ineligible special row or an unavailable destination: no unintended entry is written and the user receives appropriate disabled/error feedback.
- If meals are eligible, duplicate a meal and verify its component snapshot and nested edit/delete behavior remain independent of the source.

## High-level implementation details

1. Keep long-press and accessibility duplication on logged rows, and expose the same action in multi-select mode. Preserve the selected-date semantics while targeting the device-local current day.
2. Use one validated engine batch operation for single and multiple entries; clone each logged snapshot with fresh identity/timestamp/order and nested component IDs.
3. Expose the operation from `DiaryStore` through an atomic scope that includes selected historical IDs and destination-day rows. Surface blocked-day feedback and refresh through normal store publication.
4. Keep **Duplicate Today** in the selection action bar and integrate the single-row menu with the diary collection's existing UIKit reorder gesture; verify both are accessible and do not interfere with reorder/delete.
5. Cover successful multi-row duplication, invalid-batch atomicity, source preservation, historical source dates, special-row exclusion, and single/multi-select UI behavior. Update architecture and product documentation when behavior is documented there.

Risks include gesture conflicts in the `UIViewRepresentable` collection adapter, stale source entries during an asynchronous write, and carrying nested configuration snapshots without sharing mutable identities. The full selection must be validated before mutation so an invalid member cannot leave a partial batch.
