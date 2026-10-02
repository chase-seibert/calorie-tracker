import Foundation

enum FoodMetadataSource: String, Codable, Hashable, Sendable {
    case user, imported, catalog, nameRule, unknown, legacy

    var isAutomatic: Bool { self == .catalog || self == .nameRule || self == .unknown }
}

struct FoodMeatResolution: Codable, Hashable, Sendable {
    var processed: FoodMetadataSource
    var red: FoodMetadataSource
    var inputName: String
    var matchedFoodID: String? = nil
    var catalogVersion: String? = nil
    var version = 1
}

struct FoodCatalogIdentity: Codable, Hashable, Sendable, CodingKey {
    let source: FoodSource
    let sourceID: String

    var stringValue: String { "\(source.rawValue):\(sourceID)" }
    var intValue: Int? { nil }

    init?(stringValue: String) {
        guard let separator = stringValue.firstIndex(of: ":") else { return nil }
        let sourceValue = String(stringValue[..<separator])
        guard let source = FoodSource(rawValue: sourceValue), source == .usda || source == .openFoodFacts else {
            return nil
        }
        let sourceID = String(stringValue[stringValue.index(after: separator)...])
        guard !sourceID.isEmpty else { return nil }
        self.source = source
        self.sourceID = sourceID
    }

    init?(intValue: Int) { return nil }

    init?(food: Food) {
        guard food.source == .usda || food.source == .openFoodFacts else { return nil }
        source = food.source
        sourceID = food.sourceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identity = FoodCatalogIdentity(stringValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid corpus food identity.")
        }
        self = identity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

struct FoodMeatOverrides: Codable, Equatable, Hashable, Sendable {
    var processed: Bool?
    var red: Bool?
}

struct FoodResolutionReview: Identifiable, Sendable {
    let id = UUID()
    let food: Food
    let suggestion: Food
}

/// Classification enrichment only. Never changes identity, nutrition, quantities or portions.
struct FoodResolver: Sendable {
    let catalog: CatalogStore?

    func resolve(_ original: Food) -> Food {
        var food = original
        var provenance = food.meatResolution ?? FoodMeatResolution(
            processed: food.containsProcessedMeat == nil ? .unknown : .legacy,
            red: food.containsRedMeat == nil ? .unknown : .legacy, inputName: food.name)
        if provenance.inputName != food.name {
            if provenance.processed.isAutomatic { food.containsProcessedMeat = nil }
            if provenance.red.isAutomatic { food.containsRedMeat = nil }
            provenance.matchedFoodID = nil
            provenance.inputName = food.name
        }
        guard food.containsProcessedMeat == nil || food.containsRedMeat == nil else {
            // A fully classified legacy/catalog snapshot must round-trip byte-for-field unchanged.
            if original.meatResolution != nil { food.meatResolution = provenance }
            return food
        }

        let match = catalogMatch(food)
        let rule = Self.nameClassification(food.name)
        // Rules can identify obvious qualifiers even if a catalog record is incorrectly classified.
        // A disagreement is unresolved, never an arbitrary first-result choice.
        func value(_ catalogValue: Bool?, _ ruleValue: Bool?) -> (Bool?, FoodMetadataSource) {
            if let catalogValue, let ruleValue, catalogValue != ruleValue { return (nil, .unknown) }
            if let catalogValue { return (catalogValue, .catalog) }
            if let ruleValue { return (ruleValue, .nameRule) }
            return (nil, .unknown)
        }
        if food.containsProcessedMeat == nil {
            (food.containsProcessedMeat, provenance.processed) = value(match?.processed, rule?.containsProcessedMeat)
        }
        if food.containsRedMeat == nil {
            (food.containsRedMeat, provenance.red) = value(match?.red, rule?.containsRedMeat)
        }
        provenance.matchedFoodID = match?.id
        provenance.catalogVersion = match == nil ? nil : catalog?.catalogVersion
        food.meatResolution = provenance
        return food
    }

    func suggestion(for food: Food) -> Food {
        var candidate = food
        candidate.containsProcessedMeat = nil
        candidate.containsRedMeat = nil
        candidate.meatResolution = nil
        return resolve(candidate)
    }

    func applying(_ overrides: FoodMeatOverrides, to food: Food) -> Food {
        var candidate = food
        candidate.containsProcessedMeat = overrides.processed
        candidate.containsRedMeat = overrides.red
        candidate.meatResolution = FoodMeatResolution(
            processed: overrides.processed == nil ? .unknown : .user,
            red: overrides.red == nil ? .unknown : .user, inputName: food.name)
        return resolve(candidate)
    }

    private func catalogMatch(_ food: Food) -> (processed: Bool?, red: Bool?, id: String?)? {
        guard let catalog else { return nil }
        if food.source != .custom, let exact = catalog.food(sourceID: food.sourceID, source: food.source) {
            return (exact.containsProcessedMeat, exact.containsRedMeat, exact.id)
        }
        if let barcode = food.barcode, let exact = catalog.food(barcode: barcode) {
            return (exact.containsProcessedMeat, exact.containsRedMeat, exact.id)
        }
        let name = Self.normalized(food.name)
        // Aliases identify generic ingredients, not recipes or an exact nutrient-bearing preparation.
        let aliases = ["bacon": "pork cured bacon", "cooked bacon": "pork cured bacon cooked",
                       "turkey bacon": "bacon turkey", "scallions": "onions spring",
                       "garbanzo beans": "chickpeas"]
        let query = aliases[name] ?? name
        let results = catalog.searchAll(query, limit: 80)
        let exact = results.filter { Self.normalized($0.name) == name }
        if results.count == 80 && exact.isEmpty { return nil } // Don't infer consensus from a truncated search.
        let candidates: [Food]
        if !exact.isEmpty {
            candidates = exact
        } else {
            candidates = results.filter { candidate in
                let candidateName = Self.normalized(candidate.name)
                guard Self.compatible(query: name, candidate: candidateName) else { return false }
                if aliases[name] != nil {
                    return candidateName.hasPrefix(query) || (name == "turkey bacon" && candidateName.hasPrefix("bacon turkey"))
                }
                // Only a comma-delimited ingredient head, never a word buried in a mixed dish.
                return Self.normalized(candidate.name.components(separatedBy: ",").first ?? "") == name
            }
        }
        guard !candidates.isEmpty else { return nil }
        func consensus(_ values: [Bool?]) -> Bool? {
            guard let first = values.first ?? nil, values.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        return (consensus(candidates.map(\.containsProcessedMeat)), consensus(candidates.map(\.containsRedMeat)),
                candidates.count == 1 ? candidates[0].id : nil)
    }

    static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private static func compatible(query: String, candidate: String) -> Bool {
        let qualifiers = ["meatless", "vegan", "vegetarian", "plant based", "turkey", "chicken", "broth", "stock",
                          "flavor", "flavoured", "flavored", "seasoning", "raw", "cooked"]
        for qualifier in qualifiers {
            let q = (" " + query + " ").contains(" " + qualifier + " ")
            let c = (" " + candidate + " ").contains(" " + qualifier + " ")
            if q && !c { return false }
            if c && !q && qualifier != "raw" && qualifier != "cooked" { return false }
        }
        return !candidate.contains("sandwich") || query.contains("sandwich")
    }

    /// No match means unknown, not evidence of absence. Compound dishes need ingredient evidence.
    static func nameClassification(_ name: String) -> (containsProcessedMeat: Bool?, containsRedMeat: Bool?)? {
        let normalized = normalized(name)
        func has(_ pattern: String) -> Bool { normalized.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\b(?:without|no|free|flavor|flavoured|flavored|seasoning)\b"#) { return nil }
        if has(#"\b(?:vegan|vegetarian|meatless|plant based)\b"#) {
            if has(#"\bwith\b"#) { return nil }
            return (false, false)
        }
        let result = DiaryEngine.fallbackMeatClassification(for: name)
        let mixedDish = has(#"\b(?:soup|sandwich|salad|pizza|burger|bowl|plate|chili|stew)\b"#)
        if result.containsProcessedMeat || result.containsRedMeat {
            return (result.containsProcessedMeat ? true : (mixedDish ? nil : false),
                    result.containsRedMeat ? true : (mixedDish ? nil : false))
        }
        let simpleNonMeat = ["onion", "onions", "carrot", "carrots", "garlic", "kale", "white beans", "beans",
                            "pasta", "small pasta", "rice", "tomato paste", "parmesan cheese", "olive oil",
                            "water", "salt", "pepper", "milk", "egg", "eggs", "tofu", "chicken", "turkey",
                            "chicken breast", "salmon", "tuna", "beef broth", "chicken broth", "vegetable broth",
                            "low sodium chicken broth"]
        return simpleNonMeat.contains(normalized) ? (false, false) : nil
    }
}
