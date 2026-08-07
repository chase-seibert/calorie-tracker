# Frustration Log

## 2026-08-05: Restricted simulator compile has no runtime

`make sim-compile` can fail during asset catalog compilation when the
restricted environment cannot connect to CoreSimulator or discover an iOS
Simulator runtime. Use the host-side `make test` path for verification when
available; it successfully built and ran the unit tests in this environment.

## 2026-08-05: Generated SQLite inserts drifted from schemas

Two catalog experiments initially failed because positional `INSERT INTO ...
VALUES` placeholder counts did not match newly added table columns. For future
schema experiments, name the insert columns explicitly and validate each table's
row count immediately after generation.

## 2026-08-06: Spreadsheet authoring runtime was unavailable

The installed Spreadsheets skill's documented Node runtime could not load
`@oai/artifact-tool`. For the explicit XLSX export request, a self-contained
OOXML exporter was used as a fallback, then the workbook was successfully
converted to a native Google Sheet and verified.
