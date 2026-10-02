import Foundation

enum FoodSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case usda
    case openFoodFacts = "off"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "Open Food Facts"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "OFF"
        case .custom: "Mine"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FoodSource(rawValue: rawValue) ?? .custom
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct MacroNutrients: Codable, Hashable, Sendable {
    var calories: Double
    var carbs: Double
    var fat: Double
    var protein: Double
    var fiber: Double?

    static let zero = MacroNutrients(calories: 0, carbs: 0, fat: 0, protein: 0, fiber: 0)

    init(
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil
    ) {
        self.calories = calories
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.fiber = fiber
    }

    private enum CodingKeys: String, CodingKey {
        case calories
        case carbs
        case fat
        case protein
        case fiber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calories = try container.decode(Double.self, forKey: .calories)
        carbs = try container.decode(Double.self, forKey: .carbs)
        fat = try container.decode(Double.self, forKey: .fat)
        protein = try container.decode(Double.self, forKey: .protein)
        fiber = try container.decodeIfPresent(Double.self, forKey: .fiber)
    }

    static func + (lhs: MacroNutrients, rhs: MacroNutrients) -> MacroNutrients {
        MacroNutrients(
            calories: lhs.calories + rhs.calories,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            protein: lhs.protein + rhs.protein,
            fiber: lhs.fiber.flatMap { leftFiber in
                rhs.fiber.map { leftFiber + $0 }
            }
        )
    }

    func scaled(by factor: Double) -> MacroNutrients {
        MacroNutrients(
            calories: calories * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            protein: protein * factor,
            fiber: fiber.map { $0 * factor }
        )
    }
}

enum DiaryEntryKind: String, Codable, Hashable, Sendable {
    case cheatDayAdjustment
}

enum DayStatusKind: String, Codable, CaseIterable, Hashable, Sendable {
    case gap
    case cheat

    var title: String {
        switch self {
        case .gap: "Gap day"
        case .cheat: "Cheat day"
        }
    }
}

enum DayStatusSource: String, Codable, Hashable, Sendable {
    case automatic
    case manual
}

struct DayStatus: Codable, Hashable, Identifiable, Sendable {
    var date: Date
    var kind: DayStatusKind
    var source: DayStatusSource
    var adjustmentCalories: Int? = nil

    var id: Date { date }
}

struct StreakSummary: Equatable, Sendable {
    let dates: [Date]
    let averageNutrients: MacroNutrients
    let minimumNutrients: MacroNutrients
    let maximumNutrients: MacroNutrients
    let frequentFoods: [FrequentFood]

    var dayCount: Int { dates.count }

    var mostPopularItem: String? { frequentFoods.first?.name }

    static let empty = StreakSummary(
        dates: [],
        averageNutrients: .zero,
        minimumNutrients: .zero,
        maximumNutrients: .zero,
        frequentFoods: []
    )
}

struct FrequentFood: Equatable, Identifiable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

struct DailyCalorieProgress: Equatable, Sendable {
    let consumed: Int
    let goal: Int?
    let remaining: Int?
    let over: Int?
    let fraction: Double?

    init(calories: Double, goal: Int?) {
        consumed = Int(calories.rounded())
        self.goal = goal.flatMap { $0 > 0 ? $0 : nil }
        if let goal = self.goal {
            let difference = goal - consumed
            remaining = max(difference, 0)
            over = max(-difference, 0)
            fraction = min(max(Double(consumed) / Double(goal), 0), 1)
        } else {
            remaining = nil
            over = nil
            fraction = nil
        }
    }

    var accessibilityLabel: String {
        if let over, over > 0 {
            return "\(consumed) calories, \(over) over"
        }
        if let remaining {
            return "\(consumed) calories, \(remaining) left"
        }
        return "\(consumed) calories"
    }
}

enum AlcoholType: String, Codable, CaseIterable, Identifiable, Sendable {
    case beer
    case wine
    case spirits
    case cocktail

    static let defaultCaloriesPerDrink = 150

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beer: "Beer"
        case .wine: "Wine"
        case .spirits: "Spirits"
        case .cocktail: "Cocktail"
        }
    }

    var caloriesPerDrink: Int {
        switch self {
        case .beer: 150
        case .wine: 125
        case .spirits: 100
        case .cocktail: 200
        }
    }
}

struct AlcoholEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var date: Date
    var drinks: Int
    var type: AlcoholType?
    var loggedAt: Date

    var caloriesPerDrink: Int {
        type?.caloriesPerDrink ?? AlcoholType.defaultCaloriesPerDrink
    }

    var calories: Int {
        drinks * caloriesPerDrink
    }

    var nutrients: MacroNutrients {
        MacroNutrients(calories: Double(calories), carbs: 0, fat: 0, protein: 0, fiber: 0)
    }
}

struct FoodPortion: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var label: String
    var grams: Double
}

struct MeatClassification: Codable, Hashable, Sendable {
    var containsProcessedMeat: Bool
    var containsRedMeat: Bool

    static let none = MeatClassification(containsProcessedMeat: false, containsRedMeat: false)
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
    var containsProcessedMeat: Bool? = nil
    var containsRedMeat: Bool? = nil
    // Optional for pre-resolution snapshots. Missing provenance is never treated as user consent to overwrite.
    var meatResolution: FoodMeatResolution? = nil

    var id: String { "\(source.rawValue):\(sourceID)" }

    var meatClassification: MeatClassification? {
        guard let containsProcessedMeat, let containsRedMeat else { return nil }
        return MeatClassification(
            containsProcessedMeat: containsProcessedMeat,
            containsRedMeat: containsRedMeat
        )
    }

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

enum NaturalFoodPortionHeuristics {
    static func preferredPortion(for food: Food) -> FoodPortion? {
        let portions = food.availablePortions
        guard !portions.isEmpty else { return nil }
        let name = normalized(food.name)

        if name.contains("butter"), !name.contains("buttermilk"), !name.contains("butterbur") {
            return first(portions, matching: ["tablespoon", "tbsp"])
                ?? first(portions, matching: ["pat"])
        }

        if isBeverage(name) {
            return beveragePortion(from: portions)
        }

        if name.contains("rice") {
            let cookedCups = portions.filter { label in
                let value = normalized(label.label)
                return value.contains("cup")
                    && !value.contains("dry")
                    && !value.contains("yield")
            }
            if let cookedCup = cookedCups.first(where: { normalized($0.label).contains("cooked") }) {
                return cookedCup
            }
            if let cup = cookedCups.first { return cup }
        }

        if name.contains("chicken") || name.contains("poultry") {
            if let piece = first(
                portions,
                matching: ["wing", "drumstick", "thigh", "breast", "tender", "nugget", "piece"]
            ) {
                return piece
            }
        }

        if isWholeProduce(name),
           let producePortion = first(
               portions,
               matching: ["item", "piece", "medium", "large", "small", "whole", "peeled"]
           ) {
            return producePortion
        }

        if let discrete = first(
            portions,
            matching: [
                "item", "piece", "slice", "bar", "egg", "stick", "packet",
                "package", "container", "fillet", "pat"
            ]
        ) {
            return discrete
        }

        return first(portions, matching: ["serving"])
    }

    private static func beveragePortion(from portions: [FoodPortion]) -> FoodPortion? {
        let candidates = portions.filter { portion in
            let label = normalized(portion.label)
            return label.contains("can") || label.contains("bottle") || label.contains("container")
        }
        return candidates.sorted { left, right in
            beverageScore(left) > beverageScore(right)
        }.first ?? first(portions, matching: ["serving"])
    }

    private static func beverageScore(_ portion: FoodPortion) -> Int {
        let label = normalized(portion.label)
        var score = 0
        if label.hasPrefix("can") { score += 40 }
        if label.contains("can or bottle") { score += 30 }
        if label.hasPrefix("bottle") { score += 20 }
        if label.contains("12 fl oz") || label.contains("12 oz") { score += 12 }
        if label.contains("16 fl oz") || label.contains("16 oz") { score += 8 }
        if label.contains("20 fl oz") || label.contains("20 oz") { score += 4 }
        return score
    }

    private static func isBeverage(_ name: String) -> Bool {
        ["beer", "soda", "soft drink", "cola", "root beer", "carbonated"].contains {
            name.contains($0)
        }
    }

    private static func isWholeProduce(_ name: String) -> Bool {
        [
            "apple", "banana", "orange", "pear", "peach", "plum", "avocado",
            "potato", "onion", "tomato", "pepper"
        ].contains { name.contains($0) }
    }

    private static func first(_ portions: [FoodPortion], matching terms: [String]) -> FoodPortion? {
        portions.first { portion in
            let label = normalized(portion.label)
            return terms.contains { label == $0 || label.contains($0) }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
    var kind: DiaryEntryKind? = nil
    // Nil means derive from the historical ingredient snapshot, not a cached meal flag.
    var processedMeatOverride: Bool? = nil
    var redMeatOverride: Bool? = nil
    // Optional chart-only correction; nil derives servings from the logged quantity.
    var meatServingsOverride: Double? = nil

    var isMeal: Bool {
        savedMealID != nil || !(mealItems?.isEmpty ?? true)
    }

    var isCheatDayAdjustment: Bool {
        kind == .cheatDayAdjustment
    }
}

struct MealItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var food: Food
    var amount: Double
    var unit: LogUnit
    var portionID: String? = nil
    var meatServingsOverride: Double? = nil
}

enum SavedMealOrigin: String, Codable, Hashable, Sendable {
    case custom
    case imported
}

struct SavedMeal: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var items: [MealItem]
    var containsProcessedMeat: Bool? = nil
    var containsRedMeat: Bool? = nil
    /// Imported meals are retained as reusable snapshots for Recent and quick logging,
    /// but are kept out of the user's hand-created Personal Library.
    var origin: SavedMealOrigin = .custom

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
        case containsProcessedMeat
        case containsRedMeat
        case origin
    }

    init(
        id: UUID,
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        origin: SavedMealOrigin = .custom
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.containsProcessedMeat = containsProcessedMeat
        self.containsRedMeat = containsRedMeat
        self.origin = origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([MealItem].self, forKey: .items)
        containsProcessedMeat = try container.decodeIfPresent(Bool.self, forKey: .containsProcessedMeat)
        containsRedMeat = try container.decodeIfPresent(Bool.self, forKey: .containsRedMeat)
        // Files written before imported meal support have no origin key and are custom meals.
        origin = try container.decodeIfPresent(SavedMealOrigin.self, forKey: .origin) ?? .custom
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(containsProcessedMeat, forKey: .containsProcessedMeat)
        try container.encodeIfPresent(containsRedMeat, forKey: .containsRedMeat)
        try container.encode(origin, forKey: .origin)
    }

    var isImported: Bool { origin == .imported }

    var resolvedContainsProcessedMeat: Bool {
        containsProcessedMeat ?? items.contains { $0.food.containsProcessedMeat == true }
    }

    var resolvedContainsRedMeat: Bool {
        containsRedMeat ?? items.contains { $0.food.containsRedMeat == true }
    }

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

struct WeeklyMeatDays: Identifiable, Equatable, Sendable {
    let weekStart: Date
    let weekEnd: Date
    let processedMeatDays: Int
    let redMeatDays: Int

    var id: Date { weekStart }
}

struct WeeklyMeatServings: Identifiable, Equatable, Sendable {
    let weekStart: Date
    let weekEnd: Date
    let processedMeatServings: Double
    let redMeatServings: Double

    var id: Date { weekStart }
}

struct MeatDayFoods: Identifiable, Equatable, Sendable {
    let date: Date
    let processedMeatItems: [MeatDayFood]
    let redMeatItems: [MeatDayFood]

    var processedMeatFoods: [String] { processedMeatItems.map(\.title) }
    var redMeatFoods: [String] { redMeatItems.map(\.title) }

    var id: Date { date }
}

struct MeatDayFoodContribution: Identifiable, Equatable, Sendable {
    let entryID: UUID
    let mealItemID: UUID?
    let amount: Double
    let unit: LogUnit
    let portionID: String?
    let calculatedServings: Double
    let servings: Double
    let hasManualServingOverride: Bool
    let isMealFallback: Bool

    var id: String { "\(entryID.uuidString)|\(mealItemID?.uuidString ?? "entry")" }
}

struct MeatDayFood: Identifiable, Equatable, Sendable {
    let title: String
    let food: Food?
    let contributions: [MeatDayFoodContribution]
    let isMealFallback: Bool

    var id: String { "\(title)|\(food?.id ?? "meal-level")|\(isMealFallback)" }
    var calculatedServings: Double { contributions.reduce(0) { $0 + $1.calculatedServings } }
    var servings: Double { contributions.reduce(0) { $0 + $1.servings } }
    var hasManualServingOverride: Bool { contributions.contains { $0.hasManualServingOverride } }
}

enum FoodPickerItem: Identifiable, Hashable, Sendable {
    case food(Food)
    case meal(SavedMeal)

    var id: String {
        switch self {
        case let .food(food): "food:\(food.id)"
        case let .meal(meal): "meal:\(meal.id.uuidString)"
        }
    }
}

enum MagicFoodTimeRange: String, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }

    var hoursDescription: String {
        switch self {
        case .breakfast: "5–11 AM"
        case .lunch: "11 AM–3 PM"
        case .dinner: "after 3 PM"
        }
    }

    init(date: Date, calendar: Calendar) {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11:
            self = .breakfast
        case 11..<15:
            self = .lunch
        default:
            self = .dinner
        }
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        Self(date: date, calendar: calendar) == self
    }
}

struct MagicFoodSuggestion: Identifiable, Hashable, Sendable {
    let items: [FoodPickerItem]

    var id: String {
        items.map(\.id).sorted().joined(separator: "|")
    }
}

struct MagicFoodSuggestionResult: Sendable {
    let suggestions: [MagicFoodSuggestion]
    let hasExcludedMatches: Bool
}

struct DiaryDocument: Codable, Sendable {
    var schemaVersion = 9
    var dailyCalorieGoal: Int? = nil
    var trackingStartDate: Date? = nil
    var dayStatuses: [DayStatus] = []
    var entries: [DiaryEntry] = []
    var favorites: [Food] = []
    var favoriteMealIDs: [UUID] = []
    var favoriteItemOrder: [String] = []
    var meals: [SavedMeal] = []
    var rememberedQuantities: [String: QuantityPreference] = [:]
    var customFoods: [Food] = []
    var customFoodNames: [String: String] = [:]
    var alcoholEntries: [AlcoholEntry] = []
    var corpusFoodMeatOverrides: [FoodCatalogIdentity: FoodMeatOverrides] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case dailyCalorieGoal
        case trackingStartDate
        case dayStatuses
        case entries
        case favorites
        case favoriteMealIDs
        case favoriteItemOrder
        case meals
        case rememberedQuantities
        case customFoods
        case customFoodNames
        case alcoholEntries
        case corpusFoodMeatOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dailyCalorieGoal = try container.decodeIfPresent(Int.self, forKey: .dailyCalorieGoal)
        trackingStartDate = try container.decodeIfPresent(Date.self, forKey: .trackingStartDate)
        dayStatuses = try container.decodeIfPresent([DayStatus].self, forKey: .dayStatuses) ?? []
        entries = try container.decodeIfPresent([DiaryEntry].self, forKey: .entries) ?? []
        favorites = try container.decodeIfPresent([Food].self, forKey: .favorites) ?? []
        favoriteMealIDs = try container.decodeIfPresent([UUID].self, forKey: .favoriteMealIDs) ?? []
        favoriteItemOrder = try container.decodeIfPresent([String].self, forKey: .favoriteItemOrder) ?? []
        meals = try container.decodeIfPresent([SavedMeal].self, forKey: .meals) ?? []
        rememberedQuantities = try container.decodeIfPresent(
            [String: QuantityPreference].self,
            forKey: .rememberedQuantities
        ) ?? [:]
        customFoods = try container.decodeIfPresent([Food].self, forKey: .customFoods) ?? []
        customFoodNames = try container.decodeIfPresent(
            [String: String].self,
            forKey: .customFoodNames
        ) ?? [:]
        alcoholEntries = try container.decodeIfPresent([AlcoholEntry].self, forKey: .alcoholEntries) ?? []
        corpusFoodMeatOverrides = try container.decodeIfPresent(
            [FoodCatalogIdentity: FoodMeatOverrides].self,
            forKey: .corpusFoodMeatOverrides
        ) ?? [:]
    }
}

struct DiaryFixture: Codable, Sendable {
    let fixtureVersion: Int
    let capturedReferenceDate: Date
    var document: DiaryDocument
}

struct FoodWeightReport: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let totalGrams: Double

        var wholeOunces: Int {
            Int((totalGrams / FoodWeightReport.gramsPerOunce).rounded(.toNearestOrAwayFromZero))
        }
    }

    static let title = "Foods by Total Weight — Last 90 Days"
    static let fileName = "foods-by-total-weight-last-90-days.md"
    private static let gramsPerOunce = 28.349_523_125

    let coverageDescription: String
    let items: [Item]

    var markdown: String {
        var lines = [
            "# \(Self.title)",
            "",
            "Diary coverage: \(coverageDescription)",
            "",
            "| Food | Weight |",
            "|---|---:|"
        ]
        lines.append(contentsOf: items.map {
            "| \(Self.escapeMarkdownTableCell($0.name)) | \(Self.formattedInteger($0.wholeOunces)) oz |"
        })
        return lines.joined(separator: "\n") + "\n"
    }

    func writeShareFile(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(Self.fileName)
        try Data(markdown.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    init(document: DiaryDocument, calendar: Calendar, referenceDate: Date) {
        let today = calendar.startOfDay(for: referenceDate)
        let firstDay = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        let savedMealsByID = Dictionary(uniqueKeysWithValues: document.meals.map { ($0.id, $0) })
        var totals: [String: Accumulator] = [:]
        var coverageStart: Date?
        var coverageEnd: Date?

        for entry in document.entries where !entry.isCheatDayAdjustment {
            let entryDay = calendar.startOfDay(for: entry.date)
            guard entryDay >= firstDay, entryDay <= today else { continue }

            var entryContributedWeight = false
            for component in Self.components(for: entry, savedMealsByID: savedMealsByID) {
                let grams = component.unit.grams(
                    for: component.amount,
                    food: component.food,
                    portionID: component.portionID
                )
                guard grams.isFinite, grams > 0 else { continue }

                let id = component.food.id
                let displayName = document.customFoodNames[id] ?? component.food.name
                let name: String
                if let brand = component.food.displayBrand {
                    name = "\(displayName) — \(brand)"
                } else {
                    name = displayName
                }

                var total = totals[id] ?? Accumulator(
                    name: name,
                    totalGrams: 0,
                    latestLogDate: entry.loggedAt
                )
                total.totalGrams += grams
                if entry.loggedAt >= total.latestLogDate {
                    total.name = name
                    total.latestLogDate = entry.loggedAt
                }
                totals[id] = total
                entryContributedWeight = true
            }

            if entryContributedWeight {
                coverageStart = min(coverageStart ?? entryDay, entryDay)
                coverageEnd = max(coverageEnd ?? entryDay, entryDay)
            }
        }

        coverageDescription = Self.coverageDescription(
            from: coverageStart,
            through: coverageEnd,
            calendar: calendar
        )
        items = totals.map { id, total in
            Item(id: id, name: total.name, totalGrams: total.totalGrams)
        }
        .sorted {
            if $0.totalGrams != $1.totalGrams { return $0.totalGrams > $1.totalGrams }
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.id < $1.id
        }
    }

    private struct Component {
        let food: Food
        let amount: Double
        let unit: LogUnit
        let portionID: String?
    }

    private struct Accumulator {
        var name: String
        var totalGrams: Double
        var latestLogDate: Date
    }

    private static func components(
        for entry: DiaryEntry,
        savedMealsByID: [UUID: SavedMeal]
    ) -> [Component] {
        if entry.isMeal {
            if let snapshot = entry.mealItems, !snapshot.isEmpty {
                return snapshot.map {
                    Component(food: $0.food, amount: $0.amount, unit: $0.unit, portionID: $0.portionID)
                }
            }
            guard let savedMealID = entry.savedMealID, let meal = savedMealsByID[savedMealID] else {
                return []
            }
            return meal.items.map {
                Component(
                    food: $0.food,
                    amount: $0.amount * entry.amount,
                    unit: $0.unit,
                    portionID: $0.portionID
                )
            }
        }

        return [Component(
            food: entry.food,
            amount: entry.amount,
            unit: entry.unit,
            portionID: entry.portionID
        )]
    }

    private static func coverageDescription(
        from start: Date?,
        through end: Date?,
        calendar: Calendar
    ) -> String {
        guard let start, let end else { return "No logged foods in the last 90 days" }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: start)
        }

        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        formatter.dateFormat = startYear == endYear ? "MMMM d" : "MMMM d, yyyy"
        let startText = formatter.string(from: start)
        formatter.dateFormat = "MMMM d, yyyy"
        return "\(startText)–\(formatter.string(from: end))"
    }

    private static func formattedInteger(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func escapeMarkdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

extension Double {
    var cleanAmount: String {
        if rounded() == self { return String(Int(self)) }
        return formatted(.number.precision(.fractionLength(0...1)))
    }
}
