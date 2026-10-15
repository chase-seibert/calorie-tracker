import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "/Users/cseibert/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const source = JSON.parse(await fs.readFile("data/chase-food/catalog.json", "utf8"));
const workbook = Workbook.create();
const summary = workbook.worksheets.add("Summary");
const foods = workbook.worksheets.add("Food Profiles");
const aliases = workbook.worksheets.add("Search Aliases");
const options = workbook.worksheets.add("Food Options");
const portions = workbook.worksheets.add("Portion Estimates");
const cerealResearch = workbook.worksheets.add("Cereal Brand Research");
for (const sheet of [summary, foods, aliases, options, portions, cerealResearch]) sheet.showGridLines = false;

const counts = Object.fromEntries(["High", "Medium", "Low", "Unavailable"].map(level => [level, source.foods.filter(f => f.confidence === level).length]));
const reviewCount = source.foods.filter(f => f.reviewRequired).length;
const optionCount = source.suggestedAdditions.length + source.baseCompositions.length;
const dateParts = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Los_Angeles",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
}).formatToParts(new Date());
const reviewDate = `${dateParts.find(part => part.type === "year").value}-${dateParts.find(part => part.type === "month").value}-${dateParts.find(part => part.type === "day").value}`;
summary.getRange("A1:B1").values = [["Chase Food · Nutrition Review", reviewDate]];
summary.getRange("A3:B14").values = [
  ["Catalog identities", source.foods.length],
  ["High confidence exact-name matches", counts.High],
  ["Medium confidence close matches", counts.Medium],
  ["Low confidence approximate matches", counts.Low],
  ["Unavailable profiles", counts.Unavailable],
  ["Needs refinement", reviewCount],
  ["Alias records", source.aliases.length],
  ["Configurable component options", optionCount],
  ["Portion mappings", source.portions.length],
  ["Dataset revision", source.datasetVersion],
  ["Nutrition source", "Existing bundled catalog plus reviewed USDA FoodData Central enrichments where available"],
  ["Workbook source", source.workbookURL],
];
summary.getRange("A16:B21").values = [
  ["Confidence method", "Direct authoritative source and portion match can be High; close but recipe-variable matches are Medium; approximate matches are Low."],
  ["Nutrition values", "Per-food evidence records document the source portion, per-100 g values, and scaling to the canonical default portion."],
  ["Limit", "Generic prepared-food records can differ from a user's recipe; unresolved composition and component amounts stay flagged for refinement."],
  ["Refinement rule", "Review every Low match, prepared dish, and record with missing fiber."],
  ["Synchronization", "This sheet is generated from data/chase-food/catalog.json, the manifest used by the app catalog builder."],
  ["Alias policy", "Brand and restaurant names point to generic canonical identities; cereal package labels are comparison evidence only, kept on the separate Cereal Brand Research tab."],
];
summary.getRange("A1:B1").format = { fill: "#243B53", font: { bold: true, color: "#FFFFFF", size: 14 } };
summary.getRange("A3:A21").format = { fill: "#E9EEF3", font: { bold: true, color: "#243B53" } };
summary.getRange("A:A").format.columnWidth = 34;
summary.getRange("B:B").format.columnWidth = 100;
summary.getRange("B16:B21").format.wrapText = true;

const headers = ["Food ID", "Canonical food", "Variations", "Options", "Included components", "Category", "Food kind", "Default unit", "Default grams", "Calories / default", "Carbs g / default", "Fat g / default", "Protein g / default", "Fiber g / default", "Confidence", "Refinement needed", "Review reason", "Matched source", "Matched source ID", "Matched catalog name", "Match basis", "Similarity", "Available in search", "Evidence source URL", "Source serving", "Evidence reviewed", "Composition decision", "Baseline match"];
const records = source.foods.map(f => [
  f.id, f.name, f.variationsSummary || "None", f.optionsSummary || "None",
  f.includedComponentsSummary || "None", f.category, f.foodKind, f.defaultUnit, f.defaultGrams,
  f.nutrients?.calories ?? null, f.nutrients?.carbs ?? null, f.nutrients?.fat ?? null,
  f.nutrients?.protein ?? null, f.nutrients?.fiber ?? null, f.confidence,
  f.reviewRequired ? "Yes" : "No", f.reviewReasons.join("; "),
  f.nutritionSource?.source ?? "", f.nutritionSource?.sourceID ?? "",
  f.nutritionSource?.name ?? "", f.nutritionSource?.matchBasis ?? "",
  f.nutritionSource?.similarity ?? null,
  f.searchEnabled === false ? "No" : "Yes",
  [
    f.nutritionEvidence?.source?.url,
    ...(f.nutritionEvidence?.source?.componentSources ?? []).map(source => source.url),
  ].filter(Boolean).join("\n"),
  f.nutritionEvidence?.source?.serving
    ? `${f.nutritionEvidence.source.serving.description} (${f.nutritionEvidence.source.serving.grams} g)` : "",
  f.nutritionEvidence?.source?.reviewedDate ?? "",
  f.nutritionEvidence?.compositionEvidence?.decision ?? "",
  f.baselineNutritionSource
    ? `${f.baselineNutritionSource.name} (${f.baselineNutritionSource.source}:${f.baselineNutritionSource.sourceID}; ${f.baselineNutritionSource.matchBasis}; ${f.baselineNutritionSource.similarity})`
    : "",
]);
foods.getRangeByIndexes(0, 0, 1, headers.length).values = [headers];
foods.getRangeByIndexes(1, 0, records.length, headers.length).values = records;
foods.freezePanes.freezeRows(1);
foods.freezePanes.freezeColumns(2);
foods.tables.add(`A1:AB${records.length + 1}`, true, "ChaseFoodProfiles").style = "TableStyleMedium2";
foods.getRange(`I2:N${records.length + 1}`).format.numberFormat = "0.00";
foods.getRange(`V2:V${records.length + 1}`).format.numberFormat = "0.00";
foods.getRange("A:A").format.columnWidth = 26;
foods.getRange("B:B").format.columnWidth = 30;
foods.getRange("C:E").format.columnWidth = 36;
foods.getRange("F:G").format.columnWidth = 24;
foods.getRange("H:H").format.columnWidth = 18;
foods.getRange("I:P").format.columnWidth = 16;
foods.getRange("Q:Q").format.columnWidth = 58;
foods.getRange("R:U").format.columnWidth = 24;
foods.getRange("V:V").format.columnWidth = 12;
foods.getRange("W:W").format.columnWidth = 18;
foods.getRange("X:X").format.columnWidth = 70;
foods.getRange("Y:Y").format.columnWidth = 28;
foods.getRange("Z:Z").format.columnWidth = 18;
foods.getRange("AA:AA").format.columnWidth = 72;
foods.getRange("AB:AB").format.columnWidth = 70;
foods.getRange(`Q2:AB${records.length + 1}`).format.wrapText = true;

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
const componentDefaultGrams = new Map(source.foods.map(f => [f.id, Number(f.defaultGrams) || 30]));
const optionRows = [
  ...source.suggestedAdditions.map(r => [
  r[0], foodNames.get(r[0]) ?? r[1], r[2], foodNames.get(r[2]) ?? r[3],
  Number(r[10]) || componentDefaultGrams.get(r[2]) || null, r[5], r[6], r[8] ?? "", r[9] ?? "multiple", Number(r[4]) || null,
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

const research = JSON.parse(await fs.readFile("data/chase-food/cereal-brand-research.json", "utf8"));
const researchHeaders = ["Brand / product", "Serving", "Serving g", "Calories", "Carbs g", "Fat g", "Protein g", "Fiber g", "Generic target ID", "Source", "Official label URL", "Research note"];
const researchRows = research.records.map(r => [
  r.brand, r.serving, r.grams, r.calories, r.carbs_g, r.fat_g, r.protein_g,
  r.fiber_g, r.genericTargetID, r.source, r.url, r.note,
]);
cerealResearch.getRangeByIndexes(0, 0, 1, researchHeaders.length).values = [researchHeaders];
cerealResearch.getRangeByIndexes(1, 0, researchRows.length, researchHeaders.length).values = researchRows;
cerealResearch.freezePanes.freezeRows(1);
cerealResearch.tables.add(`A1:L${researchRows.length + 1}`, true, "CerealBrandResearch").style = "TableStyleMedium2";
cerealResearch.getRange("A:A").format.columnWidth = 38;
cerealResearch.getRange("B:B").format.columnWidth = 22;
cerealResearch.getRange("C:H").format.columnWidth = 14;
cerealResearch.getRange("I:I").format.columnWidth = 30;
cerealResearch.getRange("J:J").format.columnWidth = 38;
cerealResearch.getRange("K:K").format.columnWidth = 64;
cerealResearch.getRange("L:L").format.columnWidth = 58;
cerealResearch.getRange(`K2:L${researchRows.length + 1}`).format.wrapText = true;

workbook.recalculate();
const file = await SpreadsheetFile.exportXlsx(workbook);
await file.save("docs/chase-food-nutrition-review.xlsx");
const inspection = await workbook.inspect({ kind: "workbook,sheet,table", maxChars: 3000, tableMaxRows: 3, tableMaxCols: 6 });
console.log(inspection.ndjson);
