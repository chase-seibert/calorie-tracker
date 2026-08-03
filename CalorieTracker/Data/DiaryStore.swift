import Combine
import Foundation

@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var document: DiaryDocument
    @Published private(set) var lastSaveError: String?

    private let fileURL: URL
    private let calendar: Calendar

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.document = Self.load(from: self.fileURL) ?? DiaryDocument()
    }

    func entries(on date: Date) -> [DiaryEntry] {
        document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    func totals(on date: Date) -> MacroNutrients {
        entries(on: date).reduce(.zero) { $0 + $1.nutrients }
    }

    func log(_ food: Food, amount: Double, unit: LogUnit, portionID: String? = nil, on date: Date) {
        let clampedAmount = max(amount, 0.01)
        let entry = DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date),
            food: food,
            amount: clampedAmount,
            unit: unit,
            nutrients: food.nutrients(for: clampedAmount, unit: unit, portionID: portionID),
            loggedAt: Date(),
            portionID: portionID
        )
        document.entries.append(entry)
        document.rememberedQuantities[food.id] = QuantityPreference(
            amount: clampedAmount,
            unit: unit,
            portionID: portionID
        )
        persist()
    }

    func delete(entryID: UUID) {
        document.entries.removeAll { $0.id == entryID }
        persist()
    }

    func preference(for food: Food) -> QuantityPreference {
        if let remembered = document.rememberedQuantities[food.id] {
            return remembered
        }
        let rawDefault = UserDefaults.standard.string(forKey: "defaultWeightUnit") ?? LogUnit.ounces.rawValue
        let unit = LogUnit(rawValue: rawDefault) ?? .ounces
        return QuantityPreference(amount: unit == .ounces ? 1 : 100, unit: unit)
    }

    func rememberPreference(_ preference: QuantityPreference, for food: Food) {
        document.rememberedQuantities[food.id] = QuantityPreference(
            amount: max(preference.amount, 0.01),
            unit: preference.unit,
            portionID: preference.portionID
        )
        persist()
    }

    func quickLog(_ food: Food, on date: Date) {
        let preference = preference(for: food)
        log(
            food,
            amount: preference.amount,
            unit: preference.unit,
            portionID: preference.portionID,
            on: date
        )
    }

    func isFavorite(_ food: Food) -> Bool {
        document.favorites.contains { $0.id == food.id }
    }

    func toggleFavorite(_ food: Food, preference: QuantityPreference? = nil) {
        if let index = document.favorites.firstIndex(where: { $0.id == food.id }) {
            document.favorites.remove(at: index)
        } else {
            document.favorites.insert(food, at: 0)
            if let preference {
                document.rememberedQuantities[food.id] = preference
            }
        }
        persist()
    }

    var recentFoods: [Food] {
        uniqueFoods(from: document.entries.sorted { $0.loggedAt > $1.loggedAt }, limit: 30)
    }

    var frequentFoods: [Food] {
        let cutoff = calendar.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let recentEntries = document.entries.filter { $0.date >= cutoff }
        let grouped = Dictionary(grouping: recentEntries, by: { $0.food.id })
        return grouped.values
            .sorted {
                if $0.count == $1.count {
                    return ($0.map(\.loggedAt).max() ?? .distantPast) > ($1.map(\.loggedAt).max() ?? .distantPast)
                }
                return $0.count > $1.count
            }
            .compactMap { $0.max(by: { $0.loggedAt < $1.loggedAt })?.food }
            .prefix(30)
            .map { $0 }
    }

    func addCustomFood(
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        servingGrams: Double
    ) -> Food {
        let food = Food(
            sourceID: UUID().uuidString,
            source: .custom,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            barcode: nil,
            nutrients: MacroNutrients(calories: calories, carbs: carbs, fat: fat, protein: protein),
            baseAmountGrams: max(servingGrams, 0.01),
            servingGrams: max(servingGrams, 0.01),
            servingDescription: "1 serving",
            portions: [FoodPortion(id: "custom-serving", label: "serving", grams: max(servingGrams, 0.01))]
        )
        document.customFoods.insert(food, at: 0)
        persist()
        return food
    }

    func saveMeal(name: String, items: [MealItem]) {
        guard !items.isEmpty else { return }
        let meal = SavedMeal(id: UUID(), name: name, items: items)
        document.meals.insert(meal, at: 0)
        persist()
    }

    func deleteCustomFood(_ food: Food) {
        document.customFoods.removeAll { $0.id == food.id }
        document.favorites.removeAll { $0.id == food.id }
        document.rememberedQuantities.removeValue(forKey: food.id)
        persist()
    }

    func deleteMeal(_ meal: SavedMeal) {
        document.meals.removeAll { $0.id == meal.id }
        persist()
    }

    func logMeal(_ meal: SavedMeal, on date: Date) {
        for item in meal.items {
            log(
                item.food,
                amount: item.amount,
                unit: item.unit,
                portionID: item.portionID,
                on: date
            )
        }
    }

    func searchPersonalFoods(_ query: String) -> [Food] {
        let all = document.importedFoods
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return Array(all.prefix(50)) }
        return all.filter {
            $0.name.localizedStandardContains(normalized) ||
                ($0.brand?.localizedStandardContains(normalized) ?? false)
        }.prefix(50).map { $0 }
    }

    @discardableResult
    func importMyFitnessPal(data: Data) throws -> ImportSummary {
        let result = try MyFitnessPalImporter.parse(data: data, calendar: calendar)
        document.entries.append(contentsOf: result.entries)
        let existingIDs = Set(document.importedFoods.map(\.id))
        document.importedFoods.append(contentsOf: result.foods.filter { !existingIDs.contains($0.id) })
        persist()
        return ImportSummary(entries: result.entries.count, foods: result.foods.count, skipped: result.skipped)
    }

    func clearPersonalData() {
        document = DiaryDocument()
        persist()
    }

    func totalsByDay(numberOfDays: Int = 30) -> [(date: Date, nutrients: MacroNutrients)] {
        let today = calendar.startOfDay(for: Date())
        return (0..<numberOfDays).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, totals(on: date))
        }
    }

    private func uniqueFoods(from entries: [DiaryEntry], limit: Int) -> [Food] {
        var seen = Set<String>()
        var foods: [Food] = []
        for entry in entries where seen.insert(entry.food.id).inserted {
            foods.append(entry.food)
            if foods.count == limit { break }
        }
        return foods
    }

    private func persist() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(document).write(to: fileURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    private static func load(from fileURL: URL) -> DiaryDocument? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiaryDocument.self, from: data)
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CalorieTracker", isDirectory: true)
            .appendingPathComponent("Diary.json")
    }
}
