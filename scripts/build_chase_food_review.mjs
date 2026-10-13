import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "/Users/cseibert/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const source = JSON.parse(await fs.readFile("data/chase-food/catalog.json", "utf8"));
const workbook = Workbook.create();
const summary = workbook.worksheets.add("Summary");
const foods = workbook.worksheets.add("Food Profiles");
const aliases = workbook.worksheets.add("Search Aliases");
const options = workbook.worksheets.add("Food Options");
const portions = workbook.worksheets.add("Portion Estimates");
for (const sheet of [summary, foods, aliases, options, portions]) sheet.showGridLines = false;

const counts = Object.fromEntries(["High", "Medium", "Low", "Unavailable"].map(level => [level, source.foods.filter(f => f.confidence === level).length]));
const reviewCount = source.foods.filter(f => f.reviewRequired).length;
const optionCount = source.suggestedAdditions.length + source.baseCompositions.length;
summary.getRange("A1:B1").values = [["Chase Food · Nutrition Review", "2026-10-13"]];
summary.getRange("A3:B14").values = [
  ["Canonical identities", source.foods.length],
  ["High confidence exact-name matches", counts.High],
  ["Medium confidence close matches", counts.Medium],
  ["Low confidence approximate matches", counts.Low],
  ["Unavailable profiles", counts.Unavailable],
  ["Needs refinement", reviewCount],
  ["Alias records", source.aliases.length],
  ["Configurable component options", optionCount],
  ["Portion mappings", source.portions.length],
  ["Dataset revision", source.datasetVersion],
  ["Nutrition source", "Existing bundled USDA / Open Food Facts catalog"],
  ["Workbook source", source.workbookURL],
];
summary.getRange("A16:B21").values = [
  ["Confidence method", "High = exact canonical name; Medium = close lexical match (>=0.78); Low = approximate match (<0.78)."],
  ["Nutrition values", "Existing matched record values scaled to each workbook default gram estimate."],
  ["Limit", "These matches are screening estimates. They are not reviewed recipe analyses or product-label values."],
  ["Refinement rule", "Review every Low match, prepared dish, and record with missing fiber."],
  ["Synchronization", "This sheet is generated from data/chase-food/catalog.json, the manifest used by the app catalog builder."],
  ["Alias policy", "Brand and restaurant names point to generic canonical identities; no brand-specific nutrient claim."],
];
summary.getRange("A1:B1").format = { fill: "#243B53", font: { bold: true, color: "#FFFFFF", size: 14 } };
summary.getRange("A3:A21").format = { fill: "#E9EEF3", font: { bold: true, color: "#243B53" } };
summary.getRange("A:A").format.columnWidth = 34;
summary.getRange("B:B").format.columnWidth = 100;
summary.getRange("B16:B21").format.wrapText = true;

const headers = ["Food ID", "Canonical food", "Category", "Food kind", "Default unit", "Default grams", "Calories / default", "Carbs g / default", "Fat g / default", "Protein g / default", "Fiber g / default", "Confidence", "Refinement needed", "Review reason", "Matched source", "Matched source ID", "Matched catalog name", "Match basis", "Similarity", "Available in search"];
const records = source.foods.map(f => [
  f.id, f.name, f.category, f.foodKind, f.defaultUnit, f.defaultGrams,
  f.nutrients?.calories ?? null, f.nutrients?.carbs ?? null, f.nutrients?.fat ?? null,
  f.nutrients?.protein ?? null, f.nutrients?.fiber ?? null, f.confidence,
  f.reviewRequired ? "Yes" : "No", f.reviewReasons.join("; "),
  f.nutritionSource?.source ?? "", f.nutritionSource?.sourceID ?? "",
  f.nutritionSource?.name ?? "", f.nutritionSource?.matchBasis ?? "",
  f.nutritionSource?.similarity ?? null, f.searchEnabled === false ? "No" : "Yes",
]);
foods.getRangeByIndexes(0, 0, 1, headers.length).values = [headers];
foods.getRangeByIndexes(1, 0, records.length, headers.length).values = records;
foods.freezePanes.freezeRows(1);
foods.freezePanes.freezeColumns(2);
foods.tables.add(`A1:T${records.length + 1}`, true, "ChaseFoodProfiles").style = "TableStyleMedium2";
foods.getRange(`F2:K${records.length + 1}`).format.numberFormat = "0.00";
foods.getRange(`S2:S${records.length + 1}`).format.numberFormat = "0.00";
foods.getRange("A:A").format.columnWidth = 26;
foods.getRange("B:B").format.columnWidth = 30;
foods.getRange("C:D").format.columnWidth = 24;
foods.getRange("E:E").format.columnWidth = 18;
foods.getRange("F:M").format.columnWidth = 16;
foods.getRange("N:N").format.columnWidth = 58;
foods.getRange("O:R").format.columnWidth = 24;
foods.getRange("S:S").format.columnWidth = 12;
foods.getRange("T:T").format.columnWidth = 18;
foods.getRange(`N2:N${records.length + 1}`).format.wrapText = true;

const aliasHeaders = ["Canonical food ID", "Canonical food", "Search alias", "Alias kind"];
const names = new Map(source.foods.map(f => [f.id, f.name]));
const aliasRows = source.aliases.map(a => [a.foodID, names.get(a.foodID) ?? "", a.alias, a.kind]);
aliases.getRange("A1:D1").values = [aliasHeaders];
aliases.getRangeByIndexes(1, 0, aliasRows.length, aliasHeaders.length).values = aliasRows;
aliases.freezePanes.freezeRows(1);
aliases.freezePanes.freezeColumns(2);
aliases.tables.add(`A1:D${aliasRows.length + 1}`, true, "ChaseFoodAliases").style = "TableStyleMedium2";
aliases.getRange("A:A").format.columnWidth = 26;
aliases.getRange("B:C").format.columnWidth = 32;
aliases.getRange("D:D").format.columnWidth = 18;

const optionHeaders = ["Parent food ID", "Canonical food", "Component food ID", "Component", "Amount g", "Relationship", "Selected by default", "Option group", "Selection mode", "Display order"];
const foodNames = new Map(source.foods.map(f => [f.id, f.name]));
const optionRows = [
  ...source.suggestedAdditions.map(r => [
  r[0], foodNames.get(r[0]) ?? r[1], r[2], foodNames.get(r[2]) ?? r[3],
  Number(r[10]) || null, r[5], r[6], r[8] ?? "", r[9] ?? "multiple", Number(r[4]) || null,
  ]),
  ...source.baseCompositions.map(r => [
    r[0], foodNames.get(r[0]) ?? r[1], r[2], foodNames.get(r[2]) ?? r[3],
    Number(r[4]) || null, "Included", "Yes", "", "multiple", Number(r[5]) || null,
  ]),
];
options.getRange("A1:J1").values = [optionHeaders];
options.getRangeByIndexes(1, 0, optionRows.length, optionHeaders.length).values = optionRows;
options.freezePanes.freezeRows(1);
options.freezePanes.freezeColumns(2);
options.tables.add(`A1:J${optionRows.length + 1}`, true, "ChaseFoodOptions").style = "TableStyleMedium2";
options.getRange("A:A").format.columnWidth = 28;
options.getRange("B:B").format.columnWidth = 30;
options.getRange("C:C").format.columnWidth = 28;
options.getRange("D:D").format.columnWidth = 26;
options.getRange("E:E").format.columnWidth = 14;
options.getRange("F:I").format.columnWidth = 20;
options.getRange("J:J").format.columnWidth = 14;

const portionHeaders = ["Portion ID", "Food ID", "Canonical food", "Portion label", "Portion key", "Quantity", "Grams", "Confidence", "Notes"];
const portionRows = source.portions.map(row => [
  row[0], row[1], foodNames.get(row[1]) ?? "", row[3], row[4], Number(row[5]) || null,
  Number(row[6]) || null, row[7], row[8],
]);
portions.getRange("A1:I1").values = [portionHeaders];
portions.getRangeByIndexes(1, 0, portionRows.length, portionHeaders.length).values = portionRows;
portions.freezePanes.freezeRows(1);
portions.freezePanes.freezeColumns(3);
portions.tables.add(`A1:I${portionRows.length + 1}`, true, "ChaseFoodPortions").style = "TableStyleMedium2";
portions.getRange("A:A").format.columnWidth = 30;
portions.getRange("B:B").format.columnWidth = 26;
portions.getRange("C:D").format.columnWidth = 32;
portions.getRange("E:F").format.columnWidth = 16;
portions.getRange("G:G").format.columnWidth = 14;
portions.getRange("H:I").format.columnWidth = 28;

workbook.recalculate();
const file = await SpreadsheetFile.exportXlsx(workbook);
await file.save("docs/chase-food-nutrition-review.xlsx");
const inspection = await workbook.inspect({ kind: "workbook,sheet,table", maxChars: 3000, tableMaxRows: 3, tableMaxCols: 6 });
console.log(inspection.ndjson);
