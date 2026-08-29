# Calorie Tracker

A fast, private, local-first iPhone calorie and macro tracker. The app focuses on
three days (yesterday, today, tomorrow), makes repeated foods quick to log, and
keeps the diary and food search on-device.

## What works

- Local diary for calories, carbohydrates, fat, and protein.
- Yesterday/today/tomorrow navigation and one-tap deletion.
- Search across source-specific, on-device USDA and Open Food Facts catalogs.
- Quick logging from recents, 90-day frequency, favorites, and saved meals.
- Magic Home Screen icon actions, Siri logging and calorie-goal queries, plus
  interactive Home and Lock Screen widgets.
- Ounce-first entry, natural portions (for example, large egg and tablespoon),
  and remembered quantity for each food.
- Select any subset of diary entries and save it as a reusable meal.
- Barcode scanning and manual barcode entry.
- Custom foods and saved meals.
- Daily calorie and macro trend charts.
- A shareable last-90-days food-weight report with saved meals expanded into
  their individual foods.
- Automatic gap and calorie-goal-based cheat days, plus manual cheat-day
  adjustments and undo.
- A toolbar streak counter with calorie, macro, range, and most-logged-item
  reporting.
- Gap and cheat-day markers in calorie and macro trends.

## Build and run

```sh
make sim-launch
```

The default simulator and physical-device settings are in `Makefile`. See
`docs/setup-install.md` for more detail and `docs/data-sources.md` for catalog
provenance and refresh instructions.

System quick-entry behavior and Siri phrases are documented in
`docs/quick-entry.md`.

Catalog filtering and larger offline-size options are documented in
`docs/catalog-sizing.md`.

The iOS competitive landscape, positioning options, and monetization analysis
are documented in `docs/ios-calorie-tracker-market-research.md`.
