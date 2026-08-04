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
            .sorted {
                let leftOrder = $0.displayOrder ?? Int.max
                let rightOrder = $1.displayOrder ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return $0.loggedAt > $1.loggedAt
            }
    }

    func totals(on date: Date) -> MacroNutrients {
        entries(on: date).reduce(.zero) { $0 + $1.nutrients }
    }

    var dailyCalorieGoal: Int? {
        document.dailyCalorieGoal
    }

    func setDailyCalorieGoal(_ goal: Int?) {
        document.dailyCalorieGoal = goal.flatMap { $0 > 0 ? $0 : nil }
        persist()
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
            portionID: portionID,
            displayOrder: nextDisplayOrder(on: date)
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

    func deleteEntries(entryIDs: Set<UUID>) {
        guard !entryIDs.isEmpty else { return }
        document.entries.removeAll { entryIDs.contains($0.id) }
        persist()
    }

    func updateEntry(
        entryID: UUID,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil
    ) {
        guard
            let index = document.entries.firstIndex(where: { $0.id == entryID }),
            !document.entries[index].isMeal
        else { return }

        let clampedAmount = max(amount, 0.01)
        let food = document.entries[index].food
        document.entries[index].amount = clampedAmount
        document.entries[index].unit = unit
        document.entries[index].portionID = portionID
        document.entries[index].nutrients = food.nutrients(
            for: clampedAmount,
            unit: unit,
            portionID: portionID
        )
        document.rememberedQuantities[food.id] = QuantityPreference(
            amount: clampedAmount,
            unit: unit,
            portionID: portionID
        )
        persist()
    }

    func moveEntry(
        _ entryID: UUID,
        relativeTo targetEntryID: UUID,
        placeAfterTarget: Bool,
        on date: Date
    ) {
        guard entryID != targetEntryID else { return }
        var orderedEntries = entries(on: date)
        guard let sourceIndex = orderedEntries.firstIndex(where: { $0.id == entryID }) else { return }

        let movedEntry = orderedEntries.remove(at: sourceIndex)
        guard let targetIndex = orderedEntries.firstIndex(where: { $0.id == targetEntryID }) else { return }
        let insertionIndex = targetIndex + (placeAfterTarget ? 1 : 0)
        orderedEntries.insert(movedEntry, at: insertionIndex)

        let orderByID = Dictionary(uniqueKeysWithValues: orderedEntries.enumerated().map { ($1.id, $0) })
        for index in document.entries.indices {
            if let displayOrder = orderByID[document.entries[index].id] {
                document.entries[index].displayOrder = displayOrder
            }
        }
        persist()
    }

    func moveEntry(_ entryID: UUID, toIndex destinationIndex: Int, on date: Date) {
        var orderedEntries = entries(on: date)
        guard let sourceIndex = orderedEntries.firstIndex(where: { $0.id == entryID }) else { return }

        let movedEntry = orderedEntries.remove(at: sourceIndex)
        let boundedDestination = min(max(destinationIndex, 0), orderedEntries.count)
        orderedEntries.insert(movedEntry, at: boundedDestination)
        updateDisplayOrder(using: orderedEntries)
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
        uniqueFoods(
            from: document.entries.filter { !$0.isMeal }.sorted { $0.loggedAt > $1.loggedAt },
            limit: 30
        )
    }

    var suggestedFoods: [Food] {
        let candidates = Array(recentFoods.prefix(12)) +
            Array(frequentFoods.prefix(12)) +
            document.favorites
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }.prefix(30).map { $0 }
    }

    var frequentFoods: [Food] {
        let cutoff = calendar.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let recentEntries = document.entries.filter { $0.date >= cutoff && !$0.isMeal }
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

    func saveMeal(name: String, replacing entryIDs: Set<UUID>, on date: Date) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !entryIDs.isEmpty else { return }

        let dayEntries = entries(on: date)
        let selectedEntries = dayEntries.filter { entryIDs.contains($0.id) }
        guard !selectedEntries.isEmpty else { return }

        let meal = SavedMeal(
            id: UUID(),
            name: normalizedName,
            items: selectedEntries.map {
                MealItem(
                    id: UUID(),
                    food: $0.food,
                    amount: $0.amount,
                    unit: $0.unit,
                    portionID: $0.portionID
                )
            }
        )
        let mealEntry = makeMealEntry(
            for: meal,
            on: date,
            loggedAt: selectedEntries.map(\.loggedAt).max() ?? Date()
        )

        let insertionIndex = dayEntries.firstIndex { entryIDs.contains($0.id) } ?? 0
        var replacementEntries = dayEntries.filter { !entryIDs.contains($0.id) }
        replacementEntries.insert(mealEntry, at: min(insertionIndex, replacementEntries.count))

        document.entries.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
        for (displayOrder, var entry) in replacementEntries.enumerated() {
            entry.displayOrder = displayOrder
            document.entries.append(entry)
        }
        document.meals.insert(meal, at: 0)
        persist()
    }

    func breakApartMeal(entryID: UUID) {
        guard
            let mealEntry = document.entries.first(where: { $0.id == entryID }),
            mealEntry.isMeal
        else { return }

        let items = mealEntry.mealItems ?? document.meals.first { $0.id == mealEntry.savedMealID }?.items
        guard let items, !items.isEmpty else { return }

        var dayEntries = entries(on: mealEntry.date)
        guard let mealIndex = dayEntries.firstIndex(where: { $0.id == entryID }) else { return }
        dayEntries.remove(at: mealIndex)

        let expandedEntries = items.map {
            DiaryEntry(
                id: UUID(),
                date: mealEntry.date,
                food: $0.food,
                amount: $0.amount,
                unit: $0.unit,
                nutrients: $0.food.nutrients(for: $0.amount, unit: $0.unit, portionID: $0.portionID),
                loggedAt: mealEntry.loggedAt,
                portionID: $0.portionID
            )
        }
        dayEntries.insert(contentsOf: expandedEntries, at: mealIndex)

        document.entries.removeAll { calendar.isDate($0.date, inSameDayAs: mealEntry.date) }
        for (displayOrder, var entry) in dayEntries.enumerated() {
            entry.displayOrder = displayOrder
            document.entries.append(entry)
        }
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
        guard !meal.items.isEmpty else { return }
        document.entries.append(
            makeMealEntry(
                for: meal,
                on: date,
                loggedAt: Date(),
                displayOrder: nextDisplayOrder(on: date)
            )
        )
        persist()
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

    private func nextDisplayOrder(on date: Date) -> Int {
        let firstOrder = document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .compactMap(\.displayOrder)
            .min() ?? 0
        return firstOrder - 1
    }

    private func updateDisplayOrder(using orderedEntries: [DiaryEntry]) {
        let orderByID = Dictionary(
            uniqueKeysWithValues: orderedEntries.enumerated().map { ($1.id, $0) }
        )
        for index in document.entries.indices {
            if let displayOrder = orderByID[document.entries[index].id] {
                document.entries[index].displayOrder = displayOrder
            }
        }
    }

    private func makeMealEntry(
        for meal: SavedMeal,
        on date: Date,
        loggedAt: Date,
        displayOrder: Int? = nil
    ) -> DiaryEntry {
        let nutrients = meal.items.reduce(.zero) { total, item in
            total + item.food.nutrients(
                for: item.amount,
                unit: item.unit,
                portionID: item.portionID
            )
        }
        let mealFood = Food(
            sourceID: "saved-meal-\(meal.id.uuidString)",
            source: .custom,
            name: meal.name,
            brand: nil,
            barcode: nil,
            nutrients: nutrients,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 meal",
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)]
        )
        return DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date),
            food: mealFood,
            amount: 1,
            unit: .serving,
            nutrients: nutrients,
            loggedAt: loggedAt,
            portionID: "saved-meal",
            displayOrder: displayOrder,
            savedMealID: meal.id,
            mealItems: meal.items
        )
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
