import Foundation

struct SnackFocusPreferences: Equatable, Sendable {
    var fiber: Bool
    var processedMeat: Bool
    var redMeat: Bool
    var alcohol: Bool

    func includes(_ area: SnackFocusArea) -> Bool {
        switch area {
        case .protein: true
        case .fiber: fiber
        case .processedMeat: processedMeat
        case .redMeat: redMeat
        case .alcohol: alcohol
        }
    }
}

enum SnackFocusArea: String, CaseIterable, Identifiable, Sendable {
    case protein, fiber, processedMeat, redMeat, alcohol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: "High Protein · Always Included"
        case .fiber: "Fiber"
        case .processedMeat: "Processed Meat · Alternatives"
        case .redMeat: "Red Meat · Alternatives"
        case .alcohol: "Alcohol · Alcohol-Free Pairings"
        }
    }

    var explanation: String {
        switch self {
        case .protein: "Protein-forward options, whatever your focus areas."
        case .fiber: "Nuts, beans, fruit, and whole grains help add fiber."
        case .processedMeat: "Snack swaps without cured, smoked, or deli meats."
        case .redMeat: "Alternatives to beef, pork, and lamb snacks."
        case .alcohol: "Pair these with water or unsweetened sparkling water for an alcohol-free snack break. Food does not offset alcohol's effects."
        }
    }
}

struct SnackSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let servingTip: String
    let reasons: [SnackFocusArea: String]
    var containsProcessedMeat = false
    var containsRedMeat = false

    // Opens the existing Log Food route; the query preserves identity after a title edit.
    var reminderURL: URL { URL(string: "vitachase://log-food?snack=\(id)")! }
}

struct SnackSuggestionGroup: Identifiable, Equatable, Sendable {
    let area: SnackFocusArea
    let snacks: [SnackSuggestion]
    var id: SnackFocusArea { area }
}

enum SnackSuggestions {
    // Curated, offline ideas; not inferred nutrition values or personalized medical advice.
    // Source rationale and maintenance notes: docs/snack-suggestions.md.
    static let library: [SnackSuggestion] = [
        .init(id: "greek-yogurt", name: "Plain Greek yogurt",
              servingTip: "Try a single-serving pot; choose no added sugar.",
              reasons: [.protein: "Strained yogurt is an easy protein-forward snack.",
                        .processedMeat: "A ready-to-eat alternative to deli-meat roll-ups."]),
        .init(id: "cottage-cheese", name: "Cottage cheese",
              servingTip: "Try ½ cup with cucumber or tomatoes; compare sodium labels.",
              reasons: [.protein: "A simple dairy-based protein option.",
                        .redMeat: "Provides protein without a red-meat snack."]),
        .init(id: "eggs", name: "Hard-boiled eggs",
              servingTip: "Try 2 eggs, with pepper or herbs; keep refrigerated.",
              reasons: [.protein: "An easy-to-prepare source of protein.",
                        .processedMeat: "A savory swap for jerky or meat sticks."]),
        .init(id: "edamame", name: "Shelled edamame",
              servingTip: "Try ¾ cup, steamed, with lemon and a little seasoning.",
              reasons: [.protein: "Soybeans provide plant protein.",
                        .fiber: "Soybeans supply fiber as well as protein.",
                        .redMeat: "A plant-based protein alternative to beef or pork."]),
        .init(id: "tofu", name: "Baked tofu cubes",
              servingTip: "Try ½ cup of firm tofu, baked with herbs; keep refrigerated.",
              reasons: [.protein: "Firm tofu is a versatile soy-protein snack.",
                        .processedMeat: "Season plain tofu instead of reaching for cured meat.",
                        .redMeat: "A savory plant-based alternative to red meat."]),
        .init(id: "almonds", name: "Almonds",
              servingTip: "Try a small handful (about 1 oz); choose unsalted.",
              reasons: [.fiber: "Almonds add fiber, with some plant protein too.",
                        .alcohol: "A simple, portionable snack alongside sparkling water."]),
        .init(id: "chickpeas", name: "Roasted chickpeas",
              servingTip: "Try ½ cup; roast with paprika or herbs and go easy on salt.",
              reasons: [.fiber: "Chickpeas contribute fiber and plant protein.",
                        .processedMeat: "Crunchy and savory without processed meat.",
                        .alcohol: "A crunchy option for an alcohol-free snack break."]),
        .init(id: "hummus-vegetables", name: "Hummus & crunchy vegetables",
              servingTip: "Try ¼ cup hummus with carrots, cucumber, or bell pepper.",
              reasons: [.fiber: "Chickpeas and vegetables both contribute fiber.",
                        .redMeat: "A bean-based dip in place of a meat-based snack.",
                        .alcohol: "A shareable snack plate with an alcohol-free drink."]),
        .init(id: "apple-peanut-butter", name: "Apple & peanut butter",
              servingTip: "Try one small apple with 1 tablespoon of unsweetened peanut butter.",
              reasons: [.fiber: "Keep the apple skin for fiber; peanut butter adds some protein."]),
        .init(id: "popcorn", name: "Air-popped popcorn",
              servingTip: "Try a small bowl (about 3 cups), seasoned with herbs.",
              reasons: [.fiber: "Popcorn is a whole-grain way to add fiber.",
                        .alcohol: "An easy movie-night snack with an alcohol-free drink."])
    ]

    static func groups(
        for preferences: SnackFocusPreferences,
        candidates: [SnackSuggestion] = library
    ) -> [SnackSuggestionGroup] {
        // Apply exclusions before grouping, including the always-visible protein section.
        let allowed = candidates.filter {
            !(preferences.processedMeat && $0.containsProcessedMeat)
                && !(preferences.redMeat && $0.containsRedMeat)
        }
        return SnackFocusArea.allCases.filter(preferences.includes).compactMap { area in
            let snacks = allowed.filter { $0.reasons[area] != nil }
            return snacks.isEmpty ? nil : SnackSuggestionGroup(area: area, snacks: snacks)
        }
    }

    static func selectedSnacks(
        in groups: [SnackSuggestionGroup], ids: Set<String>
    ) -> [SnackSuggestion] {
        var seen = Set<String>()
        return groups.flatMap(\.snacks).filter { ids.contains($0.id) && seen.insert($0.id).inserted }
    }
}
