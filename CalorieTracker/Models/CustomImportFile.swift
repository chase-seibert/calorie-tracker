import Foundation

struct CustomFoodDefinition: Codable, Equatable, Sendable {
    struct Nutrition: Codable, Equatable, Sendable {
        var calories: Double
        var carbohydratesGrams: Double
        var fatGrams: Double
        var proteinGrams: Double
        var fiberGrams: Double? = nil
    }

    var name: String
    var servingDescription: String
    var servingGrams: Double
    var nutrition: Nutrition
    var notes: String?
    var containsProcessedMeat: Bool? = nil
    var containsRedMeat: Bool? = nil
    // Review-only state, deliberately not accepted from the interchange file.
    var processedMeatWasEdited = false
    var redMeatWasEdited = false

    private enum CodingKeys: String, CodingKey {
        case name, servingDescription, servingGrams, nutrition, notes, containsProcessedMeat, containsRedMeat
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 120 else {
            throw CustomImportError.invalidName
        }
        guard !servingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              servingDescription.count <= 120,
              servingGrams.isFinite,
              servingGrams > 0,
              servingGrams <= 10_000 else {
            throw CustomImportError.invalidServing
        }

        let nutrientValues = [
            nutrition.calories,
            nutrition.carbohydratesGrams,
            nutrition.fatGrams,
            nutrition.proteinGrams,
            nutrition.fiberGrams
        ]
        guard nutrientValues.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              nutrition.calories <= 10_000,
              nutrition.carbohydratesGrams <= 1_000,
              nutrition.fatGrams <= 1_000,
              nutrition.proteinGrams <= 1_000,
              (nutrition.fiberGrams ?? 0) <= 1_000 else {
            throw CustomImportError.invalidNutrition
        }
    }

    func makeFood(sourceID: String = UUID().uuidString) -> Food {
        let normalized = normalized()
        let grams = max(normalized.servingGrams, 0.01)
        return Food(
            sourceID: sourceID,
            source: .custom,
            name: normalized.name,
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(
                calories: normalized.nutrition.calories,
                carbs: normalized.nutrition.carbohydratesGrams,
                fat: normalized.nutrition.fatGrams,
                protein: normalized.nutrition.proteinGrams,
                fiber: normalized.nutrition.fiberGrams
            ),
            baseAmountGrams: grams,
            servingGrams: grams,
            servingDescription: "1 \(normalized.servingDescription)",
            portions: [FoodPortion(
                id: "imported-serving",
                label: normalized.servingDescription,
                grams: grams
            )],
            containsProcessedMeat: normalized.containsProcessedMeat,
            containsRedMeat: normalized.containsRedMeat,
            meatResolution: FoodMeatResolution(
                processed: normalized.containsProcessedMeat == nil ? .unknown : (processedMeatWasEdited ? .user : .imported),
                red: normalized.containsRedMeat == nil ? .unknown : (redMeatWasEdited ? .user : .imported),
                inputName: normalized.name)
        )
    }

    func normalized() -> CustomFoodDefinition {
        var food = self
        food.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        food.servingDescription = servingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        food.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if food.notes?.isEmpty == true {
            food.notes = nil
        }
        return food
    }
}

struct CustomMealFile: Codable, Equatable, Sendable {
    static let formatIdentifier = "calorie-tracker-meal"
    static let currentVersion = 1

    var format: String
    var version: Int
    var name: String
    var foods: [CustomFoodDefinition]
    var notes: String?

    func validate() throws {
        guard format == Self.formatIdentifier else {
            throw CustomImportError.wrongFormat
        }
        guard version == Self.currentVersion else {
            throw CustomImportError.unsupportedVersion(version)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 120 else {
            throw CustomImportError.invalidName
        }
        guard !foods.isEmpty, foods.count <= 50 else {
            throw CustomImportError.invalidFoodCount
        }
        for food in foods {
            try food.validate()
        }
    }

    func makeMeal(id: UUID = UUID()) -> SavedMeal {
        let normalizedMeal = normalized()
        return SavedMeal(
            id: id,
            name: normalizedMeal.name,
            items: normalizedMeal.foods.map { definition in
                let food = definition.makeFood()
                return MealItem(
                    id: UUID(),
                    food: food,
                    amount: 1,
                    unit: .serving,
                    portionID: food.availablePortions.first?.id
                )
            },
            origin: .imported
        )
    }

    func normalized() -> CustomMealFile {
        var meal = self
        meal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.foods = foods.map { $0.normalized() }
        meal.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if meal.notes?.isEmpty == true {
            meal.notes = nil
        }
        return meal
    }
}

enum CustomImportFile {
    static let maximumFileSize = 256 * 1_024

    static func attachmentFilename(
        for mealName: String,
        uniqueSuffix: String = UUID().uuidString.lowercased()
    ) -> String {
        let folded = mealName
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var slug = ""
        var needsSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSeparator, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        let safeSlug = slug.isEmpty ? "meal" : slug
        let safeSuffix = uniqueSuffix.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
        let suffix = safeSuffix.isEmpty ? UUID().uuidString.lowercased() : safeSuffix
        return "\(safeSlug)-\(suffix).calmeal"
    }

    static let assistantPrompt = """
    Analyze the pictured food manually and create exactly one downloadable Yum Chase `.calmeal` JSON attachment. `.calmeal` is the only supported import format. Always represent the whole serving as one named meal with one or more food components; even a simple single food must be one meal containing one component. Never create a food-only file or multiple files.

    Generate a fresh filename for every attachment from a normalized readable meal-name slug and a new collision-resistant UUID suffix, for example `chicken-and-rice-<fresh-uuid>.calmeal`. Lowercase the slug, replace runs of spaces or punctuation with hyphens, preserve readable letters and digits, and retain the `.calmeal` extension. Do not reuse a filename from an earlier estimate.

    Use this version 1 format:
    {
      "format": "calorie-tracker-meal",
      "version": 1,
      "name": "Concise meal name",
      "foods": [
        {
          "name": "First food or dish component",
          "servingDescription": "portion eaten",
          "servingGrams": 170,
          "nutrition": {
            "calories": 300,
            "carbohydratesGrams": 4,
            "fatGrams": 12,
            "proteinGrams": 45,
            "fiberGrams": 2
          },
          "containsProcessedMeat": false,
          "containsRedMeat": false,
          "notes": "Optional component-specific estimate note"
        },
        {
          "name": "Second food",
          "servingDescription": "portion eaten",
          "servingGrams": 180,
          "nutrition": {
            "calories": 220,
            "carbohydratesGrams": 40,
            "fatGrams": 4,
            "proteinGrams": 8,
            "fiberGrams": 6
          }
        }
      ],
      "notes": "Short explanation of the overall estimate and biggest uncertainty"
    }

    Replace every example value with your estimate. Use numbers, not ranges. Estimate each serving weight even if uncertain. Split a meal into meaningful components and include one component even for a simple food. For dishes plausibly cooked with butter or oil or served with dressing or sauce, estimate the likely added amount and include a distinct component when it contributes material calories; do not add arbitrary fats when preparation does not support them. State uncertainty in the affected component's notes or meal notes. Make clear whether the component estimate already includes a fat or condiment, and never count it again in another component. Component nutrition must include only that component; do not add top-level nutrition because the app calculates meal totals from components. Set containsProcessedMeat to true for actual bacon, ham, sausage, or other processed meat; meatless substitutes are different foods. Red meat means unprocessed mammalian meat. Set each meat flag only when known; omit an uncertain flag instead of copying the example false. The app can resolve missing flags without replacing your nutrition estimate. Return the `.calmeal` as a downloadable UTF-8 JSON attachment, not only as a code block.
    """

    static func load(from url: URL) throws -> CustomMealFile {
        let data = try readData(from: url)

        struct Header: Decodable {
            let format: String
            let version: Int
        }

        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw CustomImportError.invalidJSON
        }

        guard header.format == CustomMealFile.formatIdentifier else {
            throw CustomImportError.wrongFormat
        }
        guard url.pathExtension.lowercased() == "calmeal" else {
            throw CustomImportError.extensionMismatch(expected: "calmeal")
        }
        let file: CustomMealFile
        do {
            file = try decoder.decode(CustomMealFile.self, from: data)
        } catch {
            throw CustomImportError.invalidJSON
        }
        try file.validate()
        return file.normalized()
    }

    private static func readData(from url: URL) throws -> Data {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumFileSize {
            throw CustomImportError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumFileSize else {
            throw CustomImportError.fileTooLarge
        }
        return data
    }
}

enum CustomImportError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidJSON
    case wrongFormat
    case unsupportedVersion(Int)
    case extensionMismatch(expected: String)
    case invalidName
    case invalidServing
    case invalidNutrition
    case invalidFoodCount

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "The import file is too large."
        case .invalidJSON:
            "The file isn’t valid Yum Chase JSON."
        case .wrongFormat:
            "This file is not a supported Yum Chase meal. Import a named meal as a .calmeal file."
        case let .unsupportedVersion(version):
            "Import file version \(version) isn’t supported by this version of the app."
        case let .extensionMismatch(expected):
            "This file’s contents require the .\(expected) filename extension."
        case .invalidName:
            "Every imported food and meal needs a valid name."
        case .invalidServing:
            "Every imported food needs a serving description and a positive serving weight."
        case .invalidNutrition:
            "Calories and macros must be valid nonnegative numbers."
        case .invalidFoodCount:
            "An imported meal must contain between 1 and 50 foods."
        }
    }
}
