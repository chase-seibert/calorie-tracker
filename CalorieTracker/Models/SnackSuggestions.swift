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

    var badgeTitle: String {
        switch self {
        case .protein: "Protein"
        case .fiber: "Fiber"
        case .processedMeat: "Processed-meat alternative"
        case .redMeat: "Red-meat alternative"
        case .alcohol: "Alcohol-free pairing"
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
                        .alcohol: "An easy movie-night snack with an alcohol-free drink."]),
        .init(id: "skyr", name: "Plain skyr",
              servingTip: "Try one single-serving container; choose no added sugar.",
              reasons: [.protein: "Skyr is a thick, protein-forward cultured dairy option.",
                        .processedMeat: "A convenient protein alternative to deli meat."]),
        .init(id: "pumpkin-seeds", name: "Pumpkin seeds",
              servingTip: "Try ¼ cup; choose unsalted or lightly salted.",
              reasons: [.protein: "Pepitas provide plant protein in a portionable snack.",
                        .fiber: "Pumpkin seeds add fiber along with plant protein.",
                        .alcohol: "A crunchy, portionable pairing for sparkling water."]),
        .init(id: "roasted-soy-nuts", name: "Roasted soy nuts",
              servingTip: "Try ¼ cup; compare sodium labels.",
              reasons: [.protein: "Roasted soybeans are a substantial plant-protein snack.",
                        .fiber: "Whole soybeans provide fiber as well as protein.",
                        .processedMeat: "A crunchy protein swap for meat sticks.",
                        .redMeat: "A plant-based alternative to a red-meat snack."]),
        .init(id: "salmon-cucumber-bites", name: "Salmon & cucumber bites",
              servingTip: "Try 2–3 oz salmon with cucumber; check smoked salmon sodium.",
              reasons: [.protein: "Salmon provides protein in a light, savory snack.",
                        .redMeat: "A fish-based alternative to a red-meat snack."]),
        .init(id: "black-bean-salsa-cups", name: "Black bean salsa cups",
              servingTip: "Try ½ cup beans with salsa and bell pepper strips.",
              reasons: [.protein: "Black beans provide plant protein and make a filling snack.",
                        .fiber: "Beans and vegetables contribute meaningful fiber.",
                        .redMeat: "A bean-based alternative to a meat-centered snack.",
                        .alcohol: "A colorful snack plate for an alcohol-free break."]),
        .init(id: "lentil-salad-cup", name: "Lentil salad cup",
              servingTip: "Try ½ cup lentils with lemon, herbs, and chopped vegetables.",
              reasons: [.protein: "Lentils provide plant protein in a make-ahead snack.",
                        .fiber: "Lentils are a concentrated source of fiber.",
                        .redMeat: "A hearty plant-based alternative to red meat."]),
        .init(id: "pear-walnuts", name: "Pear & walnuts",
              servingTip: "Try one small pear with 1 oz walnuts.",
              reasons: [.fiber: "Pear skin and walnuts contribute fiber.",
                        .alcohol: "A simple sweet-and-savory pairing for sparkling water."]),
        .init(id: "chia-pudding", name: "Chia pudding",
              servingTip: "Try ½ cup made with milk or an unsweetened alternative.",
              reasons: [.fiber: "Chia seeds add fiber and work well in a make-ahead snack."]),
        .init(id: "berries-yogurt", name: "Berries & plain yogurt",
              servingTip: "Try 1 cup berries with ½ cup plain yogurt.",
              reasons: [.protein: "Plain yogurt adds protein to a fruit snack.",
                        .fiber: "Berries contribute fiber and natural sweetness."]),
        .init(id: "avocado-toast", name: "Whole-grain toast & avocado",
              servingTip: "Try one slice with ¼ avocado; add tomato or herbs.",
              reasons: [.fiber: "Whole grains and avocado contribute fiber.",
                        .alcohol: "A satisfying savory pairing for an alcohol-free drink."]),
        .init(id: "carrots-tahini", name: "Carrots & tahini",
              servingTip: "Try 1 cup carrots with 2 tablespoons tahini dip.",
              reasons: [.fiber: "Carrots and sesame provide fiber in a crunchy snack.",
                        .redMeat: "A vegetable-and-seed alternative to a meat snack.",
                        .alcohol: "A dip-and-crunch pairing for an alcohol-free break."]),
        .init(id: "frozen-grapes-pistachios", name: "Frozen grapes & pistachios",
              servingTip: "Try 1 cup grapes with 1 oz unsalted pistachios.",
              reasons: [.fiber: "Fruit and pistachios contribute fiber.",
                        .alcohol: "A snackable sweet-and-salty pairing for sparkling water."]),
        .init(id: "overnight-oats-berries", name: "Overnight oats with berries",
              servingTip: "Try ½ cup oats with berries and plain yogurt or milk.",
              reasons: [.fiber: "Oats and berries provide a whole-grain fiber base.",
                        .alcohol: "A make-ahead snack for an alcohol-free evening routine."])
    ]

    /// Returns each eligible snack once, preserving the curated library order.
    /// Protein is always enabled; other focus areas act as filters.
    static func snacks(
        for preferences: SnackFocusPreferences,
        candidates: [SnackSuggestion] = library
    ) -> [SnackSuggestion] {
        let enabledAreas = SnackFocusArea.allCases.filter(preferences.includes)
        let allowed = candidates.filter {
            !(preferences.processedMeat && $0.containsProcessedMeat)
                && !(preferences.redMeat && $0.containsRedMeat)
        }
        return allowed.filter { snack in
            enabledAreas.contains { snack.reasons[$0] != nil }
        }
    }

    static func selectedSnacks(
        in snacks: [SnackSuggestion], ids: Set<String>
    ) -> [SnackSuggestion] {
        snacks.filter { ids.contains($0.id) }
    }
}
