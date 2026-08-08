# Changelog

- Added time-of-day Magic logging with up to four personalized food or food-set
  suggestions learned on-device from the previous 10 days.
- Expanded the default date-relative simulator fixture with Magic-ready sets in
  every time band and entries for yesterday, today, and tomorrow.
- Clarified multi-food Magic suggestions with a thin accent outline and spacing
  before the next suggestion.
- Magic suggestions now omit singles and sets that overlap food already logged
  in today's current meal window.
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
- Added switchable USDA, Open Food Facts, and MyFitnessPal food sources.
- Added fast diary logging, favorites, frequent foods, saved meals, custom foods,
  barcode scanning, CSV import, and trends.
- Added a compact SQLite FTS catalog pipeline and source documentation.
- Wrapped every log-food mode onto the screen instead of hiding modes in a
  horizontal scroller.
- Preserved all USDA/OFF portions, added ounce-first defaults, and made the
  default weight unit configurable.
- Added selective diary-item meal creation.
- Added a browsable personal catalog for custom foods and saved meals, plus
  remembered-quantity summaries in favorite and search results.
