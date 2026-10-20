# Analytics events

All events use the `calorie-tracker` namespace and the common client fields
defined by the analytics service (`eventId`, `occurredAt`, `sessionId`, app,
platform, version, and audience). Event properties are strings.

## Event catalog

| Event | When it is recorded | Properties |
| --- | --- | --- |
| `app.launched` | Once per app process | — |
| `screen.viewed` | A tracked screen appears | `screen`; selected screens also include `operation`, `origin`, `item_type`, or `initial_mode` |
| `food_picker.opened` | The log-food picker first appears | `initial_mode` |
| `food_picker.mode_selected` | Magic, Recent, Frequent, Favorites, Meals, or Scan is selected | `mode` |
| `food_log.completed` | A food, meal, imported item, or Magic item is successfully added to the diary | `item_type`, `food_kind`, `method`, `mode`, `unit`, `is_favorite`; identity, portion, and default-comparison fields described below |
| `food_log.unit_selected` | The user selects a unit or named portion in the quantity editor | `item_type`, identity, `operation`, `from_unit`, `from_portion_id`, `selected_unit`, `selected_portion_id`, `default_unit`, `default_portion_id`, `selection_changed`, `changed_from_default` |
| `diary_entry.updated` | An existing food or meal quantity is successfully changed | `item_type`, `unit` |
| `diary_entry.deleted` | One or more diary entries are removed | `item_type`; batch removal also includes `item_count` |
| `favorite.added` / `favorite.removed` | A food or meal favorite is toggled | `item_type`; foods also include `source` |
| `custom_food.created` / `custom_food.updated` / `custom_food.deleted` | A custom food mutation succeeds | `origin` |
| `meal.created` / `meal.updated` / `meal.deleted` | A saved meal mutation succeeds | `origin`; create/update also include `item_count` |
| `meal.broken_apart` | A diary meal is successfully expanded into its foods | — |
| `cheat_day.marked` / `cheat_day.cleared` | A cheat day is set or removed | `day` (`today`, `yesterday`, `past`, or `future`) |
| `calorie_adjustment.set` / `calorie_adjustment.removed` | A daily calorie adjustment is set or removed | — |
| `alcohol.saved` | An alcohol entry is successfully created or updated | `operation` |
| `alcohol.removed` | Saving zero drinks removes an alcohol entry | — |
| `health.authorization_requested` | The Apple Health connection flow begins | — |
| `health.authorization_completed` | The authorization flow returns | `result` |
| `health.sync_requested` / `health.sync_completed` | A launch, authorization, or manual full sync begins/finishes | `source`; completion also includes `result` |
| `import.opened` / `import.failed` | An import file is parsed or rejected | Successful opens include `item_type` |
| `food_search.no_match` | A completed text search returns no results | `query`, `result_count` |
| `food_search.nothing_selected` | A completed search with results ends without a diary log | `query`, `result_count` |
| `food_search.result_selected` | A user taps or quick-adds a search result | `query`, `selected_item_id`, `selected_rank`, `result_ids_above` |
| `food.suggestion_submitted` | A user submits new-food or catalog-change feedback | `kind`, `suggested_name`, `suggested_changes`, `search_query` |
| `barcode_search.no_match` | A camera or manual barcode lookup returns no result | `barcode`, `input_source` |
| `siri.quick_log.resolution_attempted` | Siri asks Yum Chase to resolve a spoken recent-food or meal query | `query`, `result_count` |
| `siri.quick_log.started` | Siri invokes the recent-food or meal logging intent | `selection_hash` |
| `siri.quick_log.completed` | Siri successfully logs the resolved item | `selection_hash`, `logged_item_count` |
| `siri.quick_log.failed` | Siri logging fails after Yum Chase receives the intent | `selection_hash`, `failure` |

Tracked `screen` values currently include `diary`, `settings`, `trends`,
`settings_snack_suggestions`,
`streak`, `food_picker`, `quantity_editor`, `alcohol_editor`,
`food_weight_report`, `custom_catalog`, `custom_food_editor`,
`saved_meal_editor`, `import_guide`, `food_import_review`,
`meal_import_review`, `meal_photo_review`, `openai_settings`, and (in Debug) `developer_diagnostics` and
`analytics_diagnostics`, plus `analytics_event_payload` when an event is opened.

## Data minimization

Feature-usage events intentionally omit food names, meal names and contents,
brands, diary quantities, nutrient and calorie values, alcohol amounts and
types, Health samples, dates, and error descriptions. Counts are used only for
coarse workflow context. Search events are explicit exceptions: failed and
successful searches send the normalized query, and barcode misses send the
normalized barcode, to improve the catalog and search ranking. Queries are
bounded to 200 characters. When a user submits catalog feedback, that explicit
action also sends their suggested food name and change description, along with
the search query that opened the form. These fields are user-authored text;
`suggested_changes` is bounded to 2,000 characters and the other properties
are bounded to 256 characters.

Siri quick-log events use the normalized, bounded query only at the resolution
stage where Siri provides it. Resolved item identifiers are represented by a
short hash, not a food or meal name. Failure values are stable categories such
as `unknown_item`, `logging_disabled`, or `database_or_unavailable`; error text
is not sent.

For `food_log.completed`, catalog foods include `source`, `source_id`, and a
12-hex-character `catalog_version` content fingerprint. Custom and imported
items use `local_item_id` instead of a user-authored name. Food events also
include `has_brand`, `has_barcode`, and `has_portions`. When available, the
selected named portion is represented by `portion_id`; quantity-editor logs
also include the initial default unit and portion plus `unit_changed_from_default`.
Search-originated logs include the one-based `selection_rank` and `query`.
Magic suggestions emit one completion per successfully logged food or meal with
a shared `group_id`.
Meals remain one event and include `item_count`, rather than emitting their
constituent foods as additional completions.

`food_log.unit_selected` includes the item identity and both the previous and
selected portion IDs, so future analysis can distinguish a remembered default
from a deliberate override. Portion IDs are identifiers only; user-authored
portion labels are not sent.

`food_search.result_selected` uses globally stable catalog source IDs for
catalog foods. User-created foods and saved meals use explicitly local IDs;
they are not treated as cross-install identities. `result_ids_above` contains
the ranked IDs shown above the selected result, bounded by the analytics event
property limit.

In Debug builds, selecting an event in analytics diagnostics displays its
canonical payload and properties. That additional payload history is not
retained in Release builds.

Events describe completed mutations wherever possible. Opening an editor or
tapping a save button is not treated as a successful food log if the diary did
not change. Health sync completion waits for the queued HealthKit work and
reports only `success` or `failure`, never the HealthKit error text.
