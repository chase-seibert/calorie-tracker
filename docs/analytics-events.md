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
| `food_log.completed` | A food, meal, imported item, or Magic item is successfully added to the diary | `item_type`, `food_kind`, `method`, `mode`, `unit`, `is_favorite`; identity and context fields described below |
| `food_log.unit_selected` | The user changes the unit in the quantity editor | `unit`, `operation` |
| `diary_entry.updated` | An existing food or meal quantity is successfully changed | `item_type`, `unit` |
| `diary_entry.deleted` | One or more diary entries are removed | `item_type`; batch removal also includes `item_count` |
| `favorite.added` / `favorite.removed` | A food or meal favorite is toggled | `item_type`; foods also include `source` |
| `custom_food.created` / `custom_food.updated` / `custom_food.deleted` | A custom food mutation succeeds | `origin` |
| `meal.created` / `meal.updated` / `meal.deleted` | A saved meal mutation succeeds | `origin`; create/update also include `item_count` |
| `meal.broken_apart` | A diary meal is successfully expanded into its foods | — |
| `cheat_day.marked` / `cheat_day.cleared` | A cheat day is set or removed | `day` (`today`, `yesterday`, `past`, or `future`) |
| `cheat_day.adjustment_set` | A cheat-day adjustment option is chosen | — |
| `alcohol.saved` | An alcohol entry is successfully created or updated | `operation` |
| `alcohol.removed` | Saving zero drinks removes an alcohol entry | — |
| `health.authorization_requested` | The Apple Health connection flow begins | — |
| `health.authorization_completed` | The authorization flow returns | `result` |
| `health.sync_requested` / `health.sync_completed` | A launch, authorization, or manual full sync begins/finishes | `source`; completion also includes `result` |
| `import.opened` / `import.failed` | An import file is parsed or rejected | Successful opens include `item_type` |
| `food_search.no_match` | A completed text search returns no results | `query`, `result_count` |
| `food_search.nothing_selected` | A completed search with results ends without a diary log | `query`, `result_count` |
| `barcode_search.no_match` | A camera or manual barcode lookup returns no result | `barcode`, `input_source` |

Tracked `screen` values currently include `diary`, `settings`, `trends`,
`streak`, `food_picker`, `quantity_editor`, `alcohol_editor`,
`food_weight_report`, `custom_catalog`, `custom_food_editor`,
`saved_meal_editor`, `import_guide`, `food_import_review`,
`meal_import_review`, and (in Debug) `developer_diagnostics` and
`analytics_diagnostics`, plus `analytics_event_payload` when an event is opened.

## Data minimization

Feature-usage events intentionally omit food names, meal names and contents,
brands, diary quantities, nutrient and calorie values, alcohol amounts and
types, Health samples, dates, and error descriptions. Counts are used only for
coarse workflow context. Search events are explicit exceptions: failed and
successful searches send the normalized query, and barcode misses send the
normalized barcode, to improve the catalog and search ranking. Queries are
bounded to 200 characters.

For `food_log.completed`, catalog foods include `source`, `source_id`, and a
12-hex-character `catalog_version` content fingerprint. Custom and imported
items use `local_item_id` instead of a user-authored name. Food events also
include `has_brand`, `has_barcode`, and `has_portions`; search-originated logs
include the one-based `selection_rank` and `query`. Magic suggestions emit one
completion per successfully logged food or meal with a shared `group_id`.
Meals remain one event and include `item_count`, rather than emitting their
constituent foods as additional completions.

In Debug builds, selecting an event in analytics diagnostics displays its
canonical payload and properties. That additional payload history is not
retained in Release builds.

Events describe completed mutations wherever possible. Opening an editor or
tapping a save button is not treated as a successful food log if the diary did
not change. Health sync completion waits for the queued HealthKit work and
reports only `success` or `failure`, never the HealthKit error text.
