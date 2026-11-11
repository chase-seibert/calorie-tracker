import Foundation

enum FoodSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case usda
    case openFoodFacts = "off"
    case chaseFood
    case custom

    static let localCatalogSources: Set<FoodSource> = [.usda, .openFoodFacts, .chaseFood]

    static var enabledLocalCatalogSources: Set<FoodSource> {
        let defaults = UserDefaults.standard
        let keys: [(FoodSource, String)] = [
            (.usda, "foodSource.enabled.usda"),
            (.openFoodFacts, "foodSource.enabled.off"),
            (.chaseFood, "foodSource.enabled.chaseFood"),
        ]
        return Set(keys.compactMap { source, key in
            let isEnabled = (defaults.object(forKey: key) as? Bool) ?? (source != .chaseFood)
            return isEnabled ? source : nil
        })
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "Open Food Facts"
        case .chaseFood: "Chase Food"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "OFF"
        case .chaseFood: "Chase"
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

struct DailyNote: Codable, Hashable, Identifiable, Sendable {
    var date: Date
    var text: String

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
    var containsAlcohol: Bool? = nil
    // Optional for pre-resolution snapshots. Missing provenance is never treated as user consent to overwrite.
    var meatResolution: FoodMeatResolution? = nil

    // Catalog-only metadata. Keep it out of diary snapshots so a catalog refresh
    // does not rewrite or enlarge existing logged-food records.
    private enum CodingKeys: String, CodingKey {
        case sourceID, source, name, brand, barcode, nutrients, baseAmountGrams
        case servingGrams, servingDescription, portions, containsProcessedMeat, containsRedMeat, meatResolution
    }

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

struct HiddenFoodRecord: Codable, Hashable, Identifiable, Sendable {
    var food: Food

    var id: String { food.id }
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
    var foodConfigurationSnapshot: FoodConfigurationSnapshot? = nil
    var mealNotes: String? = nil

    var isMeal: Bool {
        savedMealID != nil || !(mealItems?.isEmpty ?? true)
    }

    var isCheatDayAdjustment: Bool {
        kind == .cheatDayAdjustment
    }
}

struct ChaseFoodOption: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let food: Food
    let displayName: String
    let amountGrams: Double
    let relationship: String
    let includedByDefault: Bool
    let displayOrder: Int
    let optionGroup: String?
    let selectionMode: String
}

struct ChaseFoodCompanion: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let food: Food
    let displayName: String
    let displayOrder: Int
}

enum FoodConfigurationCompatibility {
    static func removingLegacyBurgerFries(
        baseFoodID: String,
        options: [ChaseFoodOption],
        selectedOptionIDs: Set<String>
    ) -> (options: [ChaseFoodOption], selectedOptionIDs: Set<String>, removedFries: Bool) {
        guard baseFoodID == "food_burger" || baseFoodID == "chaseFood:food_burger" else {
            return (options, selectedOptionIDs, false)
        }
        let friesOptionIDs = Set(options.filter { $0.food.sourceID == "food_french_fries" }.map(\.id))
        guard !friesOptionIDs.isEmpty else { return (options, selectedOptionIDs, false) }
        return (options.filter { !friesOptionIDs.contains($0.id) },
                selectedOptionIDs.subtracting(friesOptionIDs), true)
    }
}

struct FoodConfigurationSnapshot: Codable, Hashable, Sendable {
    var selectedOptionIDs: [String]
    var components: [MealItem]
    var suggestedChanges: String?
    var catalogVersion: String?
    // Frozen editor inputs. Missing on pre-editor snapshots; never infer them from adjusted nutrition.
    var baseFood: Food? = nil
    var options: [ChaseFoodOption]? = nil
    var extraComponents: [MealItem]? = nil
    var portionID: String? = nil
    var hasEditorInputs: Bool { baseFood != nil && options != nil && extraComponents != nil }
}

struct SavedFoodConfiguration: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var baseFoodID: String
    var label: String
    var selectedOptionIDs: [String]
    var components: [MealItem]
    var portionID: String?
    var createdAt: Date
    var lastUsedAt: Date
    var snapshot: FoodConfigurationSnapshot? = nil

    init(baseFoodID: String, label: String, selectedOptionIDs: [String], components: [MealItem], portionID: String?) {
        id = UUID()
        self.baseFoodID = baseFoodID
        self.label = String(label.prefix(100))
        self.selectedOptionIDs = selectedOptionIDs
        self.components = components
        self.portionID = portionID
        createdAt = Date()
        lastUsedAt = createdAt
    }
}

#if DEBUG
enum SavedCalorieAuditTarget: Hashable, Sendable {
    case customFood(Food)
    case favoriteFood(Food)
    case configuration(SavedFoodConfiguration)
    case meal(SavedMeal)
    case loggedEntry(DiaryEntry)
}

struct SavedCalorieAuditItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let calories: Double
    let target: SavedCalorieAuditTarget

    static func highCalorieItems(in document: DiaryDocument, catalog: CatalogStore, threshold: Double) -> [SavedCalorieAuditItem] {
        guard threshold.isFinite, threshold > 0 else { return [] }
        let customFoodIDs = Set(document.customFoods.map(\.id))
        var items = [SavedCalorieAuditItem]()

        func appendFood(_ food: Food, kind: String, target: SavedCalorieAuditTarget, identity: String) {
            let calories = food.nutrients(for: 1, unit: .serving, portionID: food.availablePortions.first?.id).calories
            guard calories.isFinite, calories > 0, calories >= threshold else { return }
            items.append(SavedCalorieAuditItem(id: identity, name: food.name, kind: kind, calories: calories, target: target))
        }

        for food in document.customFoods {
            appendFood(food, kind: "Custom food", target: .customFood(food), identity: "custom-food:\(food.id)")
        }
        for food in document.favorites where !customFoodIDs.contains(food.id) {
            appendFood(food, kind: "Favorite food", target: .favoriteFood(food), identity: "favorite-food:\(food.id)")
        }
        for configuration in document.savedFoodConfigurations {
            let base = configuration.snapshot?.baseFood
                ?? document.customFoods.first(where: { $0.id == configuration.baseFoodID })
                ?? document.favorites.first(where: { $0.id == configuration.baseFoodID })
                ?? catalogFood(configuration.baseFoodID, catalog: catalog)
            guard let base else { continue }
            let options = configuration.snapshot?.options
                ?? (base.source == .chaseFood ? catalog.chaseFoodOptions(for: base.sourceID) : [])
            let extras = configuration.snapshot?.extraComponents ?? configuration.components
            let calories = FoodConfigurationCalculator.nutrients(
                food: base, options: options, selected: Set(configuration.selectedOptionIDs),
                extras: extras, portionID: configuration.portionID
            ).calories
            guard calories.isFinite, calories > 0, calories >= threshold else { continue }
            items.append(SavedCalorieAuditItem(
                id: "configuration:\(configuration.id.uuidString)",
                name: "\(base.name) · \(configuration.label)", kind: "Saved configuration",
                calories: calories, target: .configuration(configuration)
            ))
        }
        for meal in document.meals {
            let calories = meal.nutrients.calories
            guard calories.isFinite, calories > 0, calories >= threshold else { continue }
            items.append(SavedCalorieAuditItem(
                id: "meal:\(meal.id.uuidString)", name: meal.name,
                kind: meal.origin == .imported ? "Imported meal template" : "Saved meal",
                calories: calories, target: .meal(meal)
            ))
        }
        for entry in document.entries where !entry.isCheatDayAdjustment {
            let calories = entry.nutrients.calories
            guard calories.isFinite, calories > 0, calories >= threshold else { continue }
            items.append(SavedCalorieAuditItem(
                id: "logged-entry:\(entry.id.uuidString)", name: entry.food.name,
                kind: "Logged entry · \(entry.date.formatted(date: .abbreviated, time: .omitted))",
                calories: calories, target: .loggedEntry(entry)
            ))
        }
        return items.sorted {
            if $0.calories != $1.calories { return $0.calories > $1.calories }
            return $0.id < $1.id
        }
    }

    private static func catalogFood(_ identity: String, catalog: CatalogStore) -> Food? {
        let parts = identity.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let source = FoodSource(rawValue: parts[0]) else { return nil }
        return catalog.food(sourceID: parts[1], source: source)
    }
}
#endif

enum FoodSuggestionKind: String, Codable, Hashable, Sendable {
    case newCanonicalFood
    case changeToFood
}

struct FoodSuggestion: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var kind: FoodSuggestionKind
    var suggestedName: String
    var suggestedChanges: String
    var searchQuery: String?
    var foodID: String?
    var createdAt: Date

    init(kind: FoodSuggestionKind, suggestedName: String, suggestedChanges: String, searchQuery: String? = nil, foodID: String? = nil) {
        id = UUID()
        self.kind = kind
        self.suggestedName = String(suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        self.suggestedChanges = String(suggestedChanges.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        self.searchQuery = searchQuery.map { String($0.prefix(200)) }
        self.foodID = foodID
        createdAt = Date()
    }
}

struct MealItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var food: Food
    var amount: Double
    var unit: LogUnit
    var portionID: String? = nil
    var meatServingsOverride: Double? = nil
    var foodConfigurationSnapshot: FoodConfigurationSnapshot? = nil
    var configurationOptionID: String? = nil
    var notes: String? = nil
    // Nil keeps the logged ingredient's original food classification.
    var processedMeatOverride: Bool? = nil
    var redMeatOverride: Bool? = nil
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
    var notes: String? = nil
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
        case notes
    }

    init(
        id: UUID,
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        origin: SavedMealOrigin = .custom,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.containsProcessedMeat = containsProcessedMeat
        self.containsRedMeat = containsRedMeat
        self.origin = origin
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([MealItem].self, forKey: .items)
        containsProcessedMeat = try container.decodeIfPresent(Bool.self, forKey: .containsProcessedMeat)
        containsRedMeat = try container.decodeIfPresent(Bool.self, forKey: .containsRedMeat)
        // Files written before imported meal support have no origin key and are custom meals.
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
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
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    var isImported: Bool { origin == .imported }

    var resolvedContainsProcessedMeat: Bool {
        containsProcessedMeat ?? items.contains { ($0.processedMeatOverride ?? $0.food.containsProcessedMeat) == true }
    }

    var resolvedContainsRedMeat: Bool {
        containsRedMeat ?? items.contains { ($0.redMeatOverride ?? $0.food.containsRedMeat) == true }
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
    var foodConfigurations: [String: SavedFoodConfiguration]

    init(items: [FoodPickerItem], foodConfigurations: [String: SavedFoodConfiguration] = [:]) {
        self.items = items
        self.foodConfigurations = foodConfigurations
    }

    var id: String {
        items.map(\.id).sorted().joined(separator: "|")
    }

    func configuration(for food: Food) -> SavedFoodConfiguration? {
        foodConfigurations[food.id]
    }
}

struct MagicFoodSuggestionResult: Sendable {
    let suggestions: [MagicFoodSuggestion]
    let hasExcludedMatches: Bool
}

struct DiaryDocument: Codable, Sendable {
    var schemaVersion = 10
    var dailyCalorieGoal: Int? = nil
    var trackingStartDate: Date? = nil
    var dayStatuses: [DayStatus] = []
    var dailyNotes: [DailyNote] = []
    var entries: [DiaryEntry] = []
    var favorites: [Food] = []
    var favoriteMealIDs: [UUID] = []
    var favoriteItemOrder: [String] = []
    var meals: [SavedMeal] = []
    var rememberedQuantities: [String: QuantityPreference] = [:]
    var customFoods: [Food] = []
    var customFoodNames: [String: String] = [:]
    var hiddenFoods: [HiddenFoodRecord] = []
    var alcoholEntries: [AlcoholEntry] = []
    var corpusFoodMeatOverrides: [FoodCatalogIdentity: FoodMeatOverrides] = [:]
    var foodSuggestions: [FoodSuggestion] = []
    var savedFoodConfigurations: [SavedFoodConfiguration] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case dailyCalorieGoal
        case trackingStartDate
        case dayStatuses
        case dailyNotes
        case entries
        case favorites
        case favoriteMealIDs
        case favoriteItemOrder
        case meals
        case rememberedQuantities
        case customFoods
        case customFoodNames
        case hiddenFoods
        case alcoholEntries
        case corpusFoodMeatOverrides
        case foodSuggestions
        case savedFoodConfigurations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dailyCalorieGoal = try container.decodeIfPresent(Int.self, forKey: .dailyCalorieGoal)
        trackingStartDate = try container.decodeIfPresent(Date.self, forKey: .trackingStartDate)
        dayStatuses = try container.decodeIfPresent([DayStatus].self, forKey: .dayStatuses) ?? []
        dailyNotes = try container.decodeIfPresent([DailyNote].self, forKey: .dailyNotes) ?? []
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
        hiddenFoods = try container.decodeIfPresent([HiddenFoodRecord].self, forKey: .hiddenFoods) ?? []
        alcoholEntries = try container.decodeIfPresent([AlcoholEntry].self, forKey: .alcoholEntries) ?? []
        corpusFoodMeatOverrides = try container.decodeIfPresent(
            [FoodCatalogIdentity: FoodMeatOverrides].self,
            forKey: .corpusFoodMeatOverrides
        ) ?? [:]
        foodSuggestions = try container.decodeIfPresent([FoodSuggestion].self, forKey: .foodSuggestions) ?? []
        savedFoodConfigurations = try container.decodeIfPresent([SavedFoodConfiguration].self, forKey: .savedFoodConfigurations) ?? []
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

/// One calculator for detail previews, configured commits, and explicit variation quick-add.
enum FoodConfigurationCalculator {
    /// Component amounts in Chase Food are authored for one reference parent portion.
    /// Named size families use Medium as that reference; single-portion foods keep
    /// their authored amounts unchanged.
    static func componentAmountGrams(for option: ChaseFoodOption, food: Food, portionID: String?) -> Double {
        let portions = food.availablePortions
        guard portions.count > 1,
              let selectedPortion = food.portion(id: portionID),
              let referencePortion = portions.first(where: {
                    $0.label.localizedCaseInsensitiveContains("medium")
                        || $0.id.localizedCaseInsensitiveContains("medium")
                })
                ?? portions.first(where: {
                    $0.label.localizedCaseInsensitiveContains("default")
                        || $0.id.localizedCaseInsensitiveContains("default")
                })
                ?? portions.first,
              referencePortion.grams > 0 else {
            return option.amountGrams
        }
        return option.amountGrams * selectedPortion.grams / referencePortion.grams
    }

    static func nutrients(food: Food, options: [ChaseFoodOption], selected: Set<String>,
                          extras: [MealItem], portionID: String?) -> MacroNutrients {
        var total = food.nutrients(for: 1, unit: .serving, portionID: portionID)
        let variant = options.first { $0.relationship.lowercased() == "variant" && selected.contains($0.id) }
        if let variant {
            total = variant.food.nutrients(for: food.portion(id: portionID)?.grams ?? food.baseAmountGrams, unit: .grams)
        }
        let hasComponentFreeBaseline = food.source == .chaseFood && food.sourceID == "food_cappuccino"
        let components = options.filter { !["style", "variant"].contains($0.relationship.lowercased()) }
        // Existing catalog profiles include their default components. Normalize that
        // baseline first, then add only the currently selected components. Cappuccino
        // is authored as component-free because its source profile was reconstructed.
        if variant == nil && !hasComponentFreeBaseline {
            for option in components where option.includedByDefault {
                let amount = componentAmountGrams(for: option, food: food, portionID: portionID)
                let value = option.food.nutrients(for: amount, unit: .grams)
                total = subtract(value, from: total)
            }
        }
        for option in components where selected.contains(option.id) {
            if variant != nil && option.includedByDefault { continue }
            let amount = componentAmountGrams(for: option, food: food, portionID: portionID)
            total = total + option.food.nutrients(for: amount, unit: .grams)
        }
        return extras.reduce(total) { $0 + $1.food.nutrients(for: $1.amount, unit: $1.unit, portionID: $1.portionID) }
    }

    private static func subtract(_ value: MacroNutrients, from total: MacroNutrients) -> MacroNutrients {
        MacroNutrients(calories: max(0, total.calories - value.calories),
            carbs: max(0, total.carbs - value.carbs), fat: max(0, total.fat - value.fat),
            protein: max(0, total.protein - value.protein),
            fiber: total.fiber.map { max(0, $0 - (value.fiber ?? 0)) })
    }

    static func configuredFood(base: Food, portionNutrients: MacroNutrients, portionID: String?) -> Food {
        var food = base
        let grams = max(base.portion(id: portionID)?.grams ?? base.baseAmountGrams, 0.001)
        food.nutrients = portionNutrients.scaled(by: base.baseAmountGrams / grams)
        return food
    }
}

enum FoodDraftError: LocalizedError {
    case missingEntry, invalidDraft, changedEntry
    var errorDescription: String? {
        switch self {
        case .missingEntry: "This logged item no longer exists. Your changes have not been saved."
        case .invalidDraft: "Enter a name and positive, finite quantities before saving."
        case .changedEntry: "This item changed while you were editing. Reopen it to use the latest values."
        }
    }
}

extension DiaryEntry {
    var foodDraft: MealItem {
        MealItem(id: id, food: food, amount: amount, unit: unit, portionID: portionID,
                 meatServingsOverride: meatServingsOverride, foodConfigurationSnapshot: foodConfigurationSnapshot,
                 processedMeatOverride: processedMeatOverride, redMeatOverride: redMeatOverride)
    }
}
