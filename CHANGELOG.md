# Changelog

## 2026-09-01

- Moved diary/history, personal library, favorites, quantities, day status, and
  alcohol state to shared transactional SQLite storage for app, Siri, and widgets.
- Added asynchronous bounded reads, explicit storage error recovery, and durable
  revision-checked HealthKit synchronization with deletion tracking.
- Added a verified one-off JSON converter, WAL-aware backups, storage safety
  checks, multi-year benchmarks, and isolated simulator databases.
- Kept small settings in UserDefaults and analytics in its existing private
  store. Added a first-launch on-device cutover with a byte-identical JSON
  backup, verified record round trip, and atomic no-replace database publication.

- Added a shareable last-90-days Markdown report that ranks foods by total
  whole-ounce weight and expands logged meals into their component foods.
- Added time-of-day Magic logging with up to four personalized food or food-set
  suggestions learned on-device from the previous 10 days.
- Expanded the default date-relative simulator fixture with Magic-ready sets in
  every time band and entries for yesterday, today, and tomorrow.
- Clarified multi-food Magic suggestions with a thin accent outline and spacing
  before the next suggestion.
- Foods logged today remain eligible for Magic, while singleton suggestions
  require a same-day historical repeat in the active time band; today's entries
  never count toward historical eligibility.
- The default Log Food search sheet now shows Magic suggestions before typing.
- Added automatic gap days and calorie-goal-based cheat days, manual cheat-day
  marking with optional calorie adjustments, and undo-to-resume logging.
- Added a lightning-bolt streak counter and streak report with calorie, macro,
  range, and most-logged-item statistics.
- Added gap and cheat-day markers to both trend charts and special-day-aware
  Apple Health synchronization.
- Added optional Apple Health writes for logged calories, carbohydrates, fat,
  and protein, with update and deletion synchronization.

## 2026-08-03

- Created the local-first SwiftUI calorie tracker.
- Added USDA and Open Food Facts food sources.
- Added fast diary logging, favorites, frequent foods, saved meals, custom foods,
  barcode scanning, and trends.
- Added a compact SQLite FTS catalog pipeline and source documentation.
- Wrapped every log-food mode onto the screen instead of hiding modes in a
  horizontal scroller.
- Preserved all USDA/OFF portions, added ounce-first defaults, and made the
  default weight unit configurable.
- Added selective diary-item meal creation.
- Added a browsable personal catalog for custom foods and saved meals, plus
  remembered-quantity summaries in favorite and search results.
