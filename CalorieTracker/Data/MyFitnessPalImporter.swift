import Foundation

struct ImportSummary: Sendable {
    let entries: Int
    let foods: Int
    let skipped: Int
}

enum MyFitnessPalImportError: LocalizedError {
    case unreadable
    case missingHeaders
    case noRows

    var errorDescription: String? {
        switch self {
        case .unreadable: "The selected file is not a readable UTF-8 CSV."
        case .missingHeaders: "The CSV needs date, food name, and calorie columns."
        case .noRows: "No importable food rows were found."
        }
    }
}

enum MyFitnessPalImporter {
    struct Result {
        let entries: [DiaryEntry]
        let foods: [Food]
        let skipped: Int
    }

    static func parse(data: Data, calendar: Calendar) throws -> Result {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MyFitnessPalImportError.unreadable
        }
        let rows = CSV.parse(text)
        guard let headers = rows.first else { throw MyFitnessPalImportError.noRows }
        let normalized = headers.map(normalizeHeader)

        guard let dateIndex = index(of: ["date", "entrydate", "day"], in: normalized),
              let nameIndex = index(of: ["foodname", "food", "name", "description"], in: normalized),
              let calorieIndex = index(of: ["calories", "calorie", "energykcal"], in: normalized) else {
            throw MyFitnessPalImportError.missingHeaders
        }

        let carbsIndex = index(of: ["carbohydrates", "carbs", "carbohydrateg"], in: normalized)
        let fatIndex = index(of: ["fat", "fatg"], in: normalized)
        let proteinIndex = index(of: ["protein", "proteing"], in: normalized)
        let amountIndex = index(of: ["amount", "quantity", "servings", "servingsize"], in: normalized)
        let brandIndex = index(of: ["brand", "brandname"], in: normalized)

        var foodsByKey: [String: Food] = [:]
        var entries: [DiaryEntry] = []
        var skipped = 0

        for row in rows.dropFirst() {
            guard let dateText = value(row, dateIndex),
                  let date = parseDate(dateText, calendar: calendar),
                  let rawName = value(row, nameIndex),
                  !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let calories = number(value(row, calorieIndex)) else {
                skipped += 1
                continue
            }

            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let brand = brandIndex.flatMap { value(row, $0) }
            let amount = amountIndex.flatMap { number(value(row, $0)) } ?? 1
            let nutrients = MacroNutrients(
                calories: calories,
                carbs: carbsIndex.flatMap { number(value(row, $0)) } ?? 0,
                fat: fatIndex.flatMap { number(value(row, $0)) } ?? 0,
                protein: proteinIndex.flatMap { number(value(row, $0)) } ?? 0
            )
            let key = "\(brand ?? "")|\(name)|\(nutrients.calories)".lowercased()
            let sourceID = String(key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }, radix: 16)
            let food = foodsByKey[key] ?? Food(
                sourceID: sourceID,
                source: .myFitnessPal,
                name: name,
                brand: brand,
                barcode: nil,
                nutrients: nutrients,
                baseAmountGrams: 1,
                servingGrams: 1,
                servingDescription: "imported serving",
                portions: [FoodPortion(id: "mfp-serving", label: "imported serving", grams: 1)]
            )
            foodsByKey[key] = food
            entries.append(DiaryEntry(
                id: UUID(),
                date: calendar.startOfDay(for: date),
                food: food,
                amount: amount,
                unit: .serving,
                nutrients: nutrients.scaled(by: amount),
                loggedAt: date,
                portionID: "mfp-serving"
            ))
        }
        guard !entries.isEmpty else { throw MyFitnessPalImportError.noRows }
        return Result(entries: entries, foods: Array(foodsByKey.values), skipped: skipped)
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func index(of aliases: [String], in headers: [String]) -> Int? {
        aliases.compactMap { headers.firstIndex(of: $0) }.first
    }

    private static func value(_ row: [String], _ index: Int) -> String? {
        guard row.indices.contains(index) else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "").filter { $0.isNumber || $0 == "." || $0 == "-" })
    }

    private static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

private enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character == "\n", !quoted {
                row.append(field.trimmingCharacters(in: .newlines))
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = next
        }
        row.append(field.trimmingCharacters(in: .newlines))
        if !row.allSatisfy(\.isEmpty) { rows.append(row) }
        return rows
    }
}
