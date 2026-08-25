#!/usr/bin/env python3
"""Export the bundled SQLite food catalog as a native-importable XLSX workbook."""

from __future__ import annotations

import json
import re
import sqlite3
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
DATABASE = ROOT / "CalorieTracker" / "Resources" / "FoodCatalog.sqlite3"
OUTPUT = ROOT / "outputs" / "calorie-tracker-food-catalog.xlsx"
INVALID_XML = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")

HEADERS = [
    "Source ID", "Source", "Food name", "Brand", "Barcode",
    "Calories / 100 g", "Carbs (g) / 100 g", "Fat (g) / 100 g",
    "Protein (g) / 100 g", "Base grams", "Serving grams",
    "Serving description", "Portions", "Contains processed meat",
    "Contains red meat", "Rank",
]


def clean(value: object) -> str:
    return escape(INVALID_XML.sub("", "" if value is None else str(value)))


def inline_cell(column: int, value: object) -> str:
    ref = f"{column_letter(column)}{{row}}"
    if value is None or value == "":
        return ""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return f'<c r="{ref}" t="n"><v>{value}</v></c>'
    return f'<c r="{ref}" t="inlineStr"><is><t>{clean(value)}</t></is></c>'


def column_letter(index: int) -> str:
    result = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        result = chr(65 + remainder) + result
    return result


def portion_text(raw: str | None) -> str:
    if not raw:
        return ""
    try:
        portions = json.loads(raw)
    except json.JSONDecodeError:
        return raw
    return "; ".join(
        f"{item.get('label', '')} ({item.get('grams', '')} g)" for item in portions
    )


def rows() -> list[list[object]]:
    connection = sqlite3.connect(f"file:{DATABASE}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    query = """
        SELECT source_id, source, name, brand, barcode, calories, carbs, fat,
               protein, base_grams, serving_grams, serving_description,
               portions_json, contains_processed_meat, contains_red_meat, rank
        FROM foods
        ORDER BY source, rank DESC, name
    """
    result: list[list[object]] = []
    for row in connection.execute(query):
        result.append([
            row["source_id"],
            {"usda": "USDA", "off": "Open Food Facts"}.get(row["source"], row["source"]),
            row["name"], row["brand"], row["barcode"],
            row["calories"], row["carbs"], row["fat"], row["protein"],
            row["base_grams"], row["serving_grams"], row["serving_description"],
            portion_text(row["portions_json"]),
            "Yes" if row["contains_processed_meat"] else "No",
            "Yes" if row["contains_red_meat"] else "No",
            row["rank"],
        ])
    connection.close()
    return result


def build_xlsx(data: list[list[object]]) -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    last_row = len(data) + 1
    last_col = column_letter(len(HEADERS))
    sheet_rows = [
        '<row r="1" ht="24" customHeight="1">'
        + ''.join(f'<c r="{column_letter(i)}1" s="1" t="inlineStr"><is><t>{clean(header)}</t></is></c>'
                  for i, header in enumerate(HEADERS, 1))
        + '</row>'
    ]
    for row_number, values in enumerate(data, 2):
        cells = []
        for col, value in enumerate(values, 1):
            cell = inline_cell(col, value).replace("{row}", str(row_number))
            if cell:
                cells.append(cell)
        sheet_rows.append(f'<row r="{row_number}">' + ''.join(cells) + '</row>')

    sheet_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheetPr><outlinePr summaryBelow="1" summaryRight="1"/></sheetPr>
  <dimension ref="A1:{last_col}{last_row}"/>
  <sheetViews><sheetView workbookViewId="0" showGridLines="1"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>
  <sheetFormatPr defaultRowHeight="18"/>
  <cols>
    <col min="1" max="1" width="18" customWidth="1"/><col min="2" max="2" width="18" customWidth="1"/>
    <col min="3" max="3" width="42" customWidth="1"/><col min="4" max="4" width="24" customWidth="1"/>
    <col min="5" max="5" width="17" customWidth="1"/><col min="6" max="11" width="15" customWidth="1"/>
    <col min="12" max="12" width="24" customWidth="1"/><col min="13" max="13" width="38" customWidth="1"/>
    <col min="14" max="14" width="10" customWidth="1"/>
  </cols>
  <sheetData>{''.join(sheet_rows)}</sheetData>
  <autoFilter ref="A1:{last_col}{last_row}"/>
  <tableParts count="1"><tablePart r:id="rId1"/></tableParts>
</worksheet>'''

    table_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="1" name="FoodCatalogTable" displayName="FoodCatalogTable" ref="A1:{last_col}{last_row}" headerRowCount="1">
  <autoFilter ref="A1:{last_col}{last_row}"/>
  <tableColumns count="{len(HEADERS)}">{''.join(f'<tableColumn id="{i}" name="{clean(header)}"/>' for i, header in enumerate(HEADERS, 1))}</tableColumns>
  <tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>
</table>'''

    styles_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1"><numFmt numFmtId="164" formatCode="0.0##"/></numFmts>
  <fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font></fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF5B9BD5"/><bgColor indexed="64"/></patternFill></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" applyFont="1" applyFill="1"/></cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>'''

    workbook_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Food Catalog" sheetId="1" r:id="rId1"/></sheets></workbook>'''
    workbook_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'''
    sheet_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table" Target="../tables/table1.xml"/></Relationships>'''
    content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/tables/table1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'''
    root_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'''

    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", root_rels)
        archive.writestr("xl/workbook.xml", workbook_xml)
        archive.writestr("xl/_rels/workbook.xml.rels", workbook_rels)
        archive.writestr("xl/styles.xml", styles_xml)
        archive.writestr("xl/worksheets/sheet1.xml", sheet_xml)
        archive.writestr("xl/worksheets/_rels/sheet1.xml.rels", sheet_rels)
        archive.writestr("xl/tables/table1.xml", table_xml)


if __name__ == "__main__":
    catalog_rows = rows()
    build_xlsx(catalog_rows)
    print(f"Wrote {len(catalog_rows):,} rows to {OUTPUT}")
