## User requirements

- As a user, I want a small gray “Add Note” link at the bottom of the logged food items, so that I can add context right where I review that day's log.
- As a user, I want the saved note to appear in that same spot with an “Edit” link, so that I can review or change the day's context without opening another screen.
- As a user, I want to see the saved note again when I return to that day, so that the context stays with its date.
- As a user, I want to clear a note I no longer need, so that outdated context is not left in my diary.

Assumption: this means one optional free-text note per calendar day. The note area sits after the logged food items and uses the existing diary screen; the task does not specify formatting, length limits, or whether notes should appear in reports or exports, so keep the first implementation scoped to the diary.

## Architecture and data model

Add a day-note value to the diary domain and `DiaryDocument`, keyed by the calendar day. Keep it separate from `DayStatus`: notes must not create or alter gap/cheat-day state. Expose the selected day's note through the existing `DiaryStore`/`DiaryEngine` flow and persist edits through the existing `DiaryRepository` transaction path so writes remain targeted and safe across app, widget, and intent connections.

Add a `daily_notes` table keyed by normalized day and advance the SQLite `user_version` with an in-place transactional migration. Extend snapshot loading and change application so day-scoped reads include the note and saving or deleting a note only updates that day's row. Add the optional collection to `DiaryDocument` with backward-compatible decoding so legacy JSON conversion and existing diaries without notes continue to load. Notes are private diary data and remain local; do not include them in HealthKit or weekly-report payloads.

## Basic test cases

- With logged food items present, verify a small gray “Add Note” link appears below the list; tap it, save a note, and verify the note replaces the link in that location with an “Edit” link.
- Edit the displayed note and revisit the day: the updated note remains below the logged food items, and the day remains an ordinary day.
- Add a note to a day with no logged foods: the note can still be added and is visible in the note area without creating a day status.
- Edit a day's note, save, and reload the diary: only the selected date has the updated text.
- Clear a note: it is removed after reload without changing logged foods, alcohol, calorie adjustments, or day status.
- Save notes on adjacent days and read each day through a day-scoped snapshot: each note remains attached to the correct calendar date, including across a daylight-saving boundary.
- Open an existing version-2 SQLite diary and migrate it: existing diary data remains intact, notes start empty, and the migrated database can be reopened.
- Decode/convert a legacy JSON diary without the new field: it loads with no notes; a diary that includes notes round-trips without losing them.
- Attempt a failed note write or stale concurrent edit: surface the save failure and keep persisted diary data intact rather than replacing the full store with a stale snapshot.

## High-level implementation details

1. Define the day-note domain representation and add it to `DiaryDocument` with a decoding default. Decide and consistently apply the repository's calendar-day normalization for identity.
2. Extend `DiaryRepository` snapshot and diff logic with a `daily_notes` table; add the version-2-to-3 migration transactionally and preserve existing rows and WAL-backed storage behavior. Include notes in document validation and JSON migration round-trip checks.
3. Add focused `DiaryEngine`/`DiaryStore` read and save/delete operations using the existing serialized mutation path and day scope. Ensure this operation does not affect day status or HealthKit work.
4. Add the note area to `DiaryView` immediately below the logged food items. Show a small gray “Add Note” link when no note exists; after saving, show the note and an “Edit” link in its place. Provide clear save, cancel, empty-note removal, and visible error handling consistent with existing diary controls.
5. Add repository/domain tests for migration, backward compatibility, date scoping, edit/delete, and write failures, plus UI coverage for creating and revisiting a note. Review weekly reports, exports, and privacy disclosures if the product later decides notes should leave the local diary.
