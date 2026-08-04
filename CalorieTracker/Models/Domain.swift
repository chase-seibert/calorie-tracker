import Foundation

enum FoodSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case usda
    case openFoodFacts = "off"
    case myFitnessPal = "mfp"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "Open Food Facts"
        case .myFitnessPal: "MyFitnessPal"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "OFF"
        case .myFitnessPal: "MFP"
        case .custom: "Mine"
        }
    }
}

struct MacroNutrients: Codable, Hashable, Sendable {
    var calories: Double
    var carbs: Double
    var fat: Double
    var protein: Double

    static let zero = MacroNutrients(calories: 0, carbs: 0, fat: 0, protein: 0)

    static func + (lhs: MacroNutrients, rhs: MacroNutrients) -> MacroNutrients {
        MacroNutrients(
            calories: lhs.calories + rhs.calories,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            protein: lhs.protein + rhs.protein
        )
    }

    func scaled(by factor: Double) -> MacroNutrients {
        MacroNutrients(
            calories: calories * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            protein: protein * factor
        )
    }
}

struct DailyCalorieProgress: Equatable, Sendable {
    let consumed: Int
    let goal: Int?

    init(calories: Double, goal: Int?) {
        consumed = Int(calories.rounded())
        self.goal = goal.flatMap { $0 > 0 ? $0 : nil }
    }

    var accessibilityLabel: String {
        if let goal {
            return "\(consumed) of \(goal) calories"
        }
        return "\(consumed) calories"
    }
}

struct FoodPortion: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var label: String
    var grams: Double
}

struct Food: Codable, Hashable, Identifiable, Sendable {
    let sourceID: String
    let source: FoodSource
    var name: String
    var brand: String?
    var barcode: String?
    var nutrients: MacroNutrients
    var baseAmountGrams: Double
    var servingGrams: Double?
    var servingDescription: String?
    var portions: [FoodPortion]? = nil

    var id: String { "\(source.rawValue):\(sourceID)" }

    var displayBrand: String? {
        guard let brand, !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return brand
    }

    var availablePortions: [FoodPortion] {
        if let portions, !portions.isEmpty { return portions }
        guard let servingGrams else { return [] }
        return [FoodPortion(
            id: "legacy-serving",
            label: servingDescription?.replacingOccurrences(
                of: #"^1\s+"#,
                with: "",
                options: .regularExpression
            ) ?? "serving",
            grams: servingGrams
        )]
    }

    func portion(id: String?) -> FoodPortion? {
        guard let id else { return availablePortions.first }
        return availablePortions.first { $0.id == id } ?? availablePortions.first
    }

    func nutrients(for amount: Double, unit: LogUnit, portionID: String? = nil) -> MacroNutrients {
        let grams = unit.grams(for: amount, food: self, portionID: portionID)
        return nutrients.scaled(by: grams / max(baseAmountGrams, 0.001))
    }
}

enum LogUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case grams = "g"
    case ounces = "oz"
    case serving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grams: "grams"
        case .ounces: "ounces"
        case .serving: "servings"
        }
    }

    func grams(for amount: Double, food: Food, portionID: String? = nil) -> Double {
        switch self {
        case .grams: amount
        case .ounces: amount * 28.349_523_125
        case .serving: amount * (food.portion(id: portionID)?.grams ?? food.servingGrams ?? food.baseAmountGrams)
        }
    }
}

struct QuantityPreference: Codable, Hashable, Sendable {
    var amount: Double
    var unit: LogUnit
    var portionID: String? = nil
}

struct DiaryEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var date: Date
    var food: Food
    var amount: Double
    var unit: LogUnit
    var nutrients: MacroNutrients
    var loggedAt: Date
    var portionID: String? = nil
    var displayOrder: Int? = nil
    var savedMealID: UUID? = nil
    var mealItems: [MealItem]? = nil

    var isMeal: Bool {
        savedMealID != nil || !(mealItems?.isEmpty ?? true)
    }
}

struct MealItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var food: Food
    var amount: Double
    var unit: LogUnit
    var portionID: String? = nil
}

struct SavedMeal: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var items: [MealItem]

    var nutrients: MacroNutrients {
        items.reduce(.zero) { total, item in
            total + item.food.nutrients(
                for: item.amount,
                unit: item.unit,
                portionID: item.portionID
            )
        }
    }
}

struct DiaryDocument: Codable, Sendable {
    var schemaVersion = 2
    var dailyCalorieGoal: Int? = nil
    var entries: [DiaryEntry] = []
    var favorites: [Food] = []
    var meals: [SavedMeal] = []
    var rememberedQuantities: [String: QuantityPreference] = [:]
    var customFoods: [Food] = []
    var importedFoods: [Food] = []
    var customFoodNames: [String: String] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case dailyCalorieGoal
        case entries
        case favorites
        case meals
        case rememberedQuantities
        case customFoods
        case importedFoods
        case customFoodNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dailyCalorieGoal = try container.decodeIfPresent(Int.self, forKey: .dailyCalorieGoal)
        entries = try container.decodeIfPresent([DiaryEntry].self, forKey: .entries) ?? []
        favorites = try container.decodeIfPresent([Food].self, forKey: .favorites) ?? []
        meals = try container.decodeIfPresent([SavedMeal].self, forKey: .meals) ?? []
        rememberedQuantities = try container.decodeIfPresent(
            [String: QuantityPreference].self,
            forKey: .rememberedQuantities
        ) ?? [:]
        customFoods = try container.decodeIfPresent([Food].self, forKey: .customFoods) ?? []
        importedFoods = try container.decodeIfPresent([Food].self, forKey: .importedFoods) ?? []
        customFoodNames = try container.decodeIfPresent(
            [String: String].self,
            forKey: .customFoodNames
        ) ?? [:]
    }
}

extension Double {
    var cleanAmount: String {
        if rounded() == self { return String(Int(self)) }
        return formatted(.number.precision(.fractionLength(0...1)))
    }
}
