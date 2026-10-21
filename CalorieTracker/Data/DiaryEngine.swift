import Foundation

final class DiaryEngine {
    var document: DiaryDocument {
        didSet { if oldValue.entries != document.entries { entriesByDay = nil } }
    }
    private let calendar: Calendar
    private let catalog: CatalogStore?
    private var entriesByDay: [Date: [DiaryEntry]]?
    private(set) var clearsPersonalData = false

    func saveFoodSuggestion(_ suggestion: FoodSuggestion) {
        guard !suggestion.suggestedName.isEmpty, !suggestion.suggestedChanges.isEmpty else { return }
        document.foodSuggestions.removeAll { $0.id == suggestion.id }
        document.foodSuggestions.append(suggestion)
    }

    func saveFoodConfiguration(_ configuration: SavedFoodConfiguration) {
        if let index = document.savedFoodConfigurations.firstIndex(where: {
            $0.baseFoodID == configuration.baseFoodID && $0.selectedOptionIDs.sorted() == configuration.selectedOptionIDs.sorted()
                && $0.portionID == configuration.portionID
                && $0.components.count == configuration.components.count
                && zip($0.components, configuration.components).allSatisfy { left, right in
                    left.food == right.food && left.amount == right.amount && left.unit == right.unit && left.portionID == right.portionID
                        && left.foodConfigurationSnapshot == right.foodConfigurationSnapshot
                        && left.processedMeatOverride == right.processedMeatOverride && left.redMeatOverride == right.redMeatOverride
                }
                && ($0.snapshot?.baseFood == nil || $0.snapshot?.baseFood == configuration.snapshot?.baseFood)
                && ($0.snapshot?.options == nil || $0.snapshot?.options == configuration.snapshot?.options)
        }) {
            var updated = document.savedFoodConfigurations[index]
            updated.lastUsedAt = Date()
            updated.snapshot = configuration.snapshot
            updated.label = configuration.label
            updated.components = configuration.components
            document.savedFoodConfigurations[index] = updated
        } else {
            document.savedFoodConfigurations.append(configuration)
        }
    }

    func deleteSavedFoodConfiguration(id: UUID) {
        document.savedFoodConfigurations.removeAll { $0.id == id }
    }

    func logConfiguredFood(
        _ food: Food,
        nutrients: MacroNutrients,
        selectedOptionIDs: [String],
        components: [MealItem],
        suggestedChanges: String?,
        portionID: String?,
        amount: Double = 1,
        unit: LogUnit = .serving,
        snapshot: FoodConfigurationSnapshot? = nil,
        companions: [Food] = [],
        on date: Date,
        allowCheatDay: Bool = false
    ) {
        let previousCount = document.entries.count
        log(food, amount: amount, unit: unit, portionID: portionID, on: date, allowCheatDay: allowCheatDay)
        guard document.entries.count > previousCount, let index = document.entries.indices.last else { return }
        document.entries[index].nutrients = nutrients
        let loggedGrams = max(unit.grams(for: amount, food: food, portionID: portionID), 0.001)
        document.entries[index].food.nutrients = nutrients.scaled(by: food.baseAmountGrams / loggedGrams)
        document.entries[index].foodConfigurationSnapshot = snapshot ?? FoodConfigurationSnapshot(
            selectedOptionIDs: selectedOptionIDs,
            components: components,
            suggestedChanges: suggestedChanges,
            catalogVersion: catalog?.catalogVersion
        )
        for companion in companions {
            quickLog(companion, on: date, allowCheatDay: allowCheatDay)
        }
    }

    init(document: DiaryDocument, calendar: Calendar = .current, catalog: CatalogStore? = nil) {
        self.calendar = calendar
        self.catalog = catalog
        self.document = document
    }

    func entries(on date: Date) -> [DiaryEntry] {
        if entriesByDay == nil {
            entriesByDay = Dictionary(grouping: document.entries) { calendar.startOfDay(for: $0.date) }
        }
        return (entriesByDay?[calendar.startOfDay(for: date)] ?? [])
            .sorted {
                let leftOrder = $0.displayOrder ?? Int.max
                let rightOrder = $1.displayOrder ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return $0.loggedAt > $1.loggedAt
            }
    }

    func totals(on date: Date) -> MacroNutrients {
        let dayEntries = entries(on: date)
        var total = dayEntries.reduce(alcoholEntry(on: date)?.nutrients ?? .zero) {
            $0 + $1.nutrients
        }
        total.fiber = dayEntries.reduce(alcoholEntry(on: date)?.nutrients.fiber ?? 0) {
            subtotal, entry in
            if let fiber = entry.nutrients.fiber {
                return subtotal + fiber
            }
            let knownMealItemFiber =
                entry.mealItems?.compactMap { item in
                    item.food.nutrients(
                        for: item.amount,
                        unit: item.unit,
                        portionID: item.portionID
                    ).fiber
                }.reduce(0, +) ?? 0
            return subtotal + knownMealItemFiber
        }
        return total
    }

    func caloriesExcludingAlcohol(on date: Date) -> Double {
        max(totals(on: date).calories - Double(alcoholEntry(on: date)?.calories ?? 0), 0)
    }

    func meatPresence(on date: Date) -> MeatClassification {
        entries(on: date).reduce(.none) { result, entry in
            guard !entry.isCheatDayAdjustment else { return result }
            let classification = entryMeatClassification(entry)
            return MeatClassification(
                containsProcessedMeat: result.containsProcessedMeat || classification.containsProcessedMeat,
                containsRedMeat: result.containsRedMeat || classification.containsRedMeat
            )
        }
    }

    func weeklyMeatDays(
        numberOfDays: Int = 30,
        referenceDate: Date = Date()
    ) -> [WeeklyMeatDays] {
        guard numberOfDays > 0 else { return [] }
        let today = calendar.startOfDay(for: referenceDate)
        var counts: [Date: (processed: Int, red: Int)] = [:]

        for offset in (0..<numberOfDays).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                let week = calendar.dateInterval(of: .weekOfYear, for: day)
            else { continue }
            let presence = meatPresence(on: day)
            var count = counts[week.start] ?? (0, 0)
            if presence.containsProcessedMeat { count.processed += 1 }
            if presence.containsRedMeat { count.red += 1 }
            counts[week.start] = count
        }

        return counts.keys.sorted().map { weekStart in
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let count = counts[weekStart] ?? (0, 0)
            return WeeklyMeatDays(
                weekStart: weekStart,
                weekEnd: weekEnd,
                processedMeatDays: count.processed,
                redMeatDays: count.red
            )
        }
    }

    func weeklyMeatServings(
        numberOfDays: Int = 30,
        referenceDate: Date = Date()
    ) -> [WeeklyMeatServings] {
        guard numberOfDays > 0 else { return [] }
        let today = calendar.startOfDay(for: referenceDate)
        var counts: [Date: (processed: Double, red: Double)] = [:]

        for offset in (0..<numberOfDays).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                let week = calendar.dateInterval(of: .weekOfYear, for: day)
            else { continue }
            let servings = meatServings(on: day)
            var count = counts[week.start] ?? (0, 0)
            count.processed += servings.processed
            count.red += servings.red
            counts[week.start] = count
        }

        return counts.keys.sorted().map { weekStart in
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let count = counts[weekStart] ?? (0, 0)
            return WeeklyMeatServings(
                weekStart: weekStart,
                weekEnd: weekEnd,
                processedMeatServings: count.processed,
                redMeatServings: count.red
            )
        }
    }

    func meatDayFoods(
        numberOfDays: Int = 30,
        referenceDate: Date = Date()
    ) -> [MeatDayFoods] {
        guard numberOfDays > 0 else { return [] }
        let today = calendar.startOfDay(for: referenceDate)
        return (0..<numberOfDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return meatFoods(on: day)
        }
    }

    private func meatServings(on date: Date) -> (processed: Double, red: Double) {
        var processed = 0.0
        var red = 0.0

        for entry in entries(on: date) where !entry.isCheatDayAdjustment {
            if let items = entry.mealItems, !items.isEmpty {
                var matchedProcessed = false
                var matchedRed = false
                for item in items {
                    let classification = mealItemMeatClassification(item)
                    let calculatedServings = servingEquivalent(
                        amount: item.amount,
                        unit: item.unit,
                        food: item.food,
                        portionID: item.portionID
                    )
                    let servings = item.meatServingsOverride ?? calculatedServings
                    if classification.containsProcessedMeat {
                        processed += servings
                        matchedProcessed = true
                    }
                    if classification.containsRedMeat {
                        red += servings
                        matchedRed = true
                    }
                }

                // Preserve an explicit meal-level classification when its historical
                // ingredients do not carry a matching flag.
                let classification = entryMeatClassification(entry)
                let fallbackServings = entry.meatServingsOverride ?? max(entry.amount, 0.01)
                if classification.containsProcessedMeat && !matchedProcessed {
                    processed += fallbackServings
                }
                if classification.containsRedMeat && !matchedRed {
                    red += fallbackServings
                }
            } else {
                let classification = entryMeatClassification(entry)
                let calculatedServings = servingEquivalent(
                    amount: entry.amount,
                    unit: entry.unit,
                    food: entry.food,
                    portionID: entry.portionID
                )
                let servings = entry.meatServingsOverride ?? calculatedServings
                if classification.containsProcessedMeat { processed += servings }
                if classification.containsRedMeat { red += servings }
            }
        }

        return (processed, red)
    }

    private func servingEquivalent(
        amount: Double,
        unit: LogUnit,
        food: Food,
        portionID: String?
    ) -> Double {
        let grams = unit.grams(for: amount, food: food, portionID: portionID)
        let servingGrams = food.portion(id: portionID)?.grams
            ?? food.servingGrams
            ?? food.baseAmountGrams
        return grams / max(servingGrams, 0.001)
    }

    func alcoholEntry(on date: Date) -> AlcoholEntry? {
        document.alcoholEntries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func alcoholDrinkCount(on date: Date) -> Int {
        alcoholEntry(on: date)?.drinks ?? 0
    }

    func setAlcohol(
        drinks: Int,
        type: AlcoholType?,
        on date: Date,
        allowCheatDay: Bool = false
    ) {
        guard allowCheatDay || canLogFood(on: date) else { return }
        let day = calendar.startOfDay(for: date)
        let previousEntry = alcoholEntry(on: day)
        let normalizedDrinks = max(drinks, 0)

        document.alcoholEntries.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        if normalizedDrinks > 0 {
            document.alcoholEntries.append(
                AlcoholEntry(
                    id: previousEntry?.id ?? UUID(),
                    date: day,
                    drinks: normalizedDrinks,
                    type: type,
                    loggedAt: previousEntry?.loggedAt ?? Date()
                ))
            clearAutomaticStatus(on: day)
        } else if day < calendar.startOfDay(for: Date()) {
            reconcileAutomaticStatus(on: day)
        }

    }

    func foodWeightReport(referenceDate: Date = Date()) -> FoodWeightReport {
        FoodWeightReport(document: document, calendar: calendar, referenceDate: referenceDate)
    }

    func status(on date: Date) -> DayStatus? {
        document.dayStatuses.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func canLogFood(on date: Date) -> Bool {
        status(on: date)?.kind != .cheat
    }

    func calorieAdjustment(on date: Date) -> Int? {
        entries(on: date)
            .first(where: \.isCheatDayAdjustment)
            .map { Int($0.nutrients.calories.rounded()) }
    }

    var dailyCalorieGoal: Int? {
        document.dailyCalorieGoal
    }

    func setDailyCalorieGoal(_ goal: Int?) {
        document.dailyCalorieGoal = goal.flatMap { $0 > 0 ? $0 : nil }
        finalizePastDays(referenceDate: Date())
    }

    func markCheatDay(on date: Date, adjustmentCalories: Int? = nil) {
        let day = calendar.startOfDay(for: date)
        let normalizedAdjustment = adjustmentCalories.flatMap { $0 > 0 ? $0 : nil }
        let existingAdjustment = calorieAdjustment(on: day)

        if let normalizedAdjustment {
            document.entries.removeAll {
                calendar.isDate($0.date, inSameDayAs: day) && $0.isCheatDayAdjustment
            }
            document.entries.append(
                makeCalorieAdjustment(
                    calories: normalizedAdjustment,
                    on: day
                ))
        }

        upsertStatus(
            DayStatus(
                date: day,
                kind: .cheat,
                source: .manual,
                adjustmentCalories: normalizedAdjustment ?? existingAdjustment
            ))

    }

    func setCalorieAdjustment(_ calories: Int?, on date: Date) {
        let day = calendar.startOfDay(for: date)
        let normalizedAdjustment = calories.flatMap { $0 > 0 ? $0 : nil }
        document.entries.removeAll {
            calendar.isDate($0.date, inSameDayAs: day) && $0.isCheatDayAdjustment
        }
        if let normalizedAdjustment {
            document.entries.append(
                makeCalorieAdjustment(
                    calories: normalizedAdjustment,
                    on: day
                ))
            clearAutomaticStatus(on: day)
        } else if day < calendar.startOfDay(for: Date()) {
            reconcileAutomaticStatus(on: day)
        }

        if let statusIndex = document.dayStatuses.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: day) && $0.kind == .cheat
        }) {
            document.dayStatuses[statusIndex].adjustmentCalories = normalizedAdjustment
        }

    }

    func undoCheatDay(on date: Date, preservingCalorieAdjustment: Bool = false) {
        guard status(on: date)?.kind == .cheat else { return }
        let day = calendar.startOfDay(for: date)
        document.dayStatuses.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        if !preservingCalorieAdjustment {
            document.entries.removeAll {
                calendar.isDate($0.date, inSameDayAs: day) && $0.isCheatDayAdjustment
            }
        }
    }

    func finalizePastDays(referenceDate: Date = Date()) {
        let today = calendar.startOfDay(for: referenceDate)
        guard
            let trackingStartDate = document.trackingStartDate.map(calendar.startOfDay(for:)),
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            trackingStartDate <= yesterday
        else { return }

        var day = trackingStartDate
        while day <= yesterday {
            reconcileAutomaticStatus(on: day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
    }

    func finalizeDay(_ date: Date) {
        reconcileAutomaticStatus(on: date)
    }

    var currentStreak: StreakSummary {
        streak(referenceDate: Date())
    }

    func streak(referenceDate: Date) -> StreakSummary {
        let today = calendar.startOfDay(for: referenceDate)
        var cursor = today

        if !hasLoggedFoodOrMeal(on: today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return .empty
            }
            cursor = yesterday
        }

        let lowerBound = document.trackingStartDate.map(calendar.startOfDay(for:)) ?? today
        var dates: [Date] = []
        while cursor >= lowerBound {
            guard hasLoggedFoodOrMeal(on: cursor) else { break }
            dates.append(cursor)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        guard !dates.isEmpty else { return .empty }
        let nutrients = dates.map(totals(on:))
        let count = Double(nutrients.count)
        let total = nutrients.reduce(.zero, +)
        let minimum = MacroNutrients(
            calories: nutrients.map(\.calories).min() ?? 0,
            carbs: nutrients.map(\.carbs).min() ?? 0,
            fat: nutrients.map(\.fat).min() ?? 0,
            protein: nutrients.map(\.protein).min() ?? 0
        )
        let maximum = MacroNutrients(
            calories: nutrients.map(\.calories).max() ?? 0,
            carbs: nutrients.map(\.carbs).max() ?? 0,
            fat: nutrients.map(\.fat).max() ?? 0,
            protein: nutrients.map(\.protein).max() ?? 0
        )

        return StreakSummary(
            dates: dates,
            averageNutrients: total.scaled(by: 1 / count),
            minimumNutrients: minimum,
            maximumNutrients: maximum,
            frequentFoods: frequentFoods(on: Set(dates))
        )
    }

    #if DEBUG
        func seedSpecialDaysForScreenshots(referenceDate: Date = Date()) {
            let today = calendar.startOfDay(for: referenceDate)
            guard
                let gapStart = calendar.date(byAdding: .day, value: -4, to: today),
                let cheatDay = calendar.date(byAdding: .day, value: -2, to: today)
            else { return }
            document.trackingStartDate = gapStart
            upsertStatus(DayStatus(date: cheatDay, kind: .cheat, source: .manual))
            finalizePastDays(referenceDate: referenceDate)
        }
    #endif

    func log(
        _ food: Food,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil,
        on date: Date,
        allowCheatDay: Bool = false
    ) {
        guard allowCheatDay || canLogFood(on: date) else { return }
        clearAutomaticStatus(on: date)
        let clampedAmount = max(amount, 0.01)
        let current = document.customFoods.first { $0.id == food.id }
            ?? document.favorites.first { $0.id == food.id } ?? food
        let foodToLog = displayedFood(current)
        let entry = DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date),
            food: foodToLog,
            amount: clampedAmount,
            unit: unit,
            nutrients: foodToLog.nutrients(for: clampedAmount, unit: unit, portionID: portionID),
            loggedAt: Date(),
            portionID: portionID,
            displayOrder: nextDisplayOrder(on: date)
        )
        document.entries.append(entry)
        document.rememberedQuantities[foodToLog.id] = QuantityPreference(
            amount: clampedAmount,
            unit: unit,
            portionID: portionID
        )
    }

    func delete(entryID: UUID) {
        let deletedEntries = document.entries.filter { $0.id == entryID && !$0.isCheatDayAdjustment }
        guard !deletedEntries.isEmpty else { return }
        document.entries.removeAll { $0.id == entryID && !$0.isCheatDayAdjustment }
    }

    func duplicateEntry(entryID: UUID, on date: Date) throws {
        try duplicateEntries(entryIDs: [entryID], on: date)
    }

    func duplicateEntries(entryIDs: Set<UUID>, on date: Date) throws {
        guard !entryIDs.isEmpty else { return }
        let sources = document.entries.filter { entryIDs.contains($0.id) }.sorted {
            let leftOrder = $0.displayOrder ?? Int.max
            let rightOrder = $1.displayOrder ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return $0.loggedAt > $1.loggedAt
        }
        guard sources.count == entryIDs.count else {
            throw DiaryDatabaseError.invalidData("A selected logged item is no longer available.")
        }
        guard !sources.contains(where: \.isCheatDayAdjustment) else {
            throw DiaryDatabaseError.invalidData("Calorie adjustments cannot be duplicated as food.")
        }
        guard canLogFood(on: date) else {
            throw DiaryDatabaseError.invalidData("Food logging is disabled for this day.")
        }

        clearAutomaticStatus(on: date)
        for source in sources {
            let clonedMealItems = source.mealItems?.map(cloningIdentity)
            let clonedConfiguration = source.foodConfigurationSnapshot.map(cloningIdentities)
            let duplicate = DiaryEntry(
                id: UUID(),
                date: calendar.startOfDay(for: date),
                food: source.food,
                amount: source.amount,
                unit: source.unit,
                nutrients: source.nutrients,
                loggedAt: Date(),
                portionID: source.portionID,
                displayOrder: nextDisplayOrder(on: date),
                // A copied meal owns its logged ingredient snapshot; later template edits
                // must not change what this diary entry represents.
                savedMealID: nil,
                mealItems: clonedMealItems,
                kind: nil,
                processedMeatOverride: source.processedMeatOverride,
                redMeatOverride: source.redMeatOverride,
                meatServingsOverride: source.meatServingsOverride,
                foodConfigurationSnapshot: clonedConfiguration,
                mealNotes: source.mealNotes
            )
            document.entries.append(duplicate)
            if !source.isMeal {
                document.rememberedQuantities[source.food.id] = QuantityPreference(
                    amount: source.amount,
                    unit: source.unit,
                    portionID: source.portionID
                )
            }
        }
    }

    private func cloningIdentity(_ item: MealItem) -> MealItem {
        MealItem(
            id: UUID(),
            food: item.food,
            amount: item.amount,
            unit: item.unit,
            portionID: item.portionID,
            meatServingsOverride: item.meatServingsOverride,
            foodConfigurationSnapshot: item.foodConfigurationSnapshot.map(cloningIdentities),
            configurationOptionID: item.configurationOptionID,
            notes: item.notes,
            processedMeatOverride: item.processedMeatOverride,
            redMeatOverride: item.redMeatOverride
        )
    }

    private func cloningIdentities(_ snapshot: FoodConfigurationSnapshot) -> FoodConfigurationSnapshot {
        var copy = snapshot
        copy.components = snapshot.components.map(cloningIdentity)
        copy.extraComponents = snapshot.extraComponents?.map(cloningIdentity)
        return copy
    }

    func deleteEntries(entryIDs: Set<UUID>) {
        guard !entryIDs.isEmpty else { return }
        document.entries.removeAll {
            entryIDs.contains($0.id) && !$0.isCheatDayAdjustment
        }
    }

    /// Commit one value draft atomically. Identity, date, order and HealthKit identity stay intact.
    func updateFoodDraft(entryID: UUID, draft: MealItem, original: DiaryEntry) throws {
        guard let index = document.entries.firstIndex(where: { $0.id == entryID }) else { throw FoodDraftError.missingEntry }
        guard document.entries[index] == original else { throw FoodDraftError.changedEntry }
        guard !original.isMeal, draft.amount.isFinite, draft.amount > 0 else { throw FoodDraftError.invalidDraft }
        if draft == original.foodDraft { return }
        document.entries[index].food = draft.food
        document.entries[index].amount = draft.amount
        document.entries[index].unit = draft.unit
        document.entries[index].portionID = draft.portionID
        document.entries[index].foodConfigurationSnapshot = draft.foodConfigurationSnapshot
        document.entries[index].processedMeatOverride = draft.processedMeatOverride
        document.entries[index].redMeatOverride = draft.redMeatOverride
        // A tags-only save preserves even historical rounding or manually adjusted totals.
        if draft.food != original.food || draft.amount != original.amount || draft.unit != original.unit || draft.portionID != original.portionID {
            if draft.food == original.food {
                let oldGrams = original.unit.grams(for: original.amount, food: original.food, portionID: original.portionID)
                let grams = draft.unit.grams(for: draft.amount, food: draft.food, portionID: draft.portionID)
                document.entries[index].nutrients = original.nutrients.scaled(by: grams / max(oldGrams, 0.001))
            } else {
                document.entries[index].nutrients = draft.food.nutrients(for: draft.amount, unit: draft.unit, portionID: draft.portionID)
            }
        }
        rememberPreference(QuantityPreference(amount: draft.amount, unit: draft.unit, portionID: draft.portionID), for: draft.food)
    }

    func updateMealDraft(original: DiaryEntry, name: String, amount: Double, items: [MealItem], processed: Bool?, red: Bool?) throws {
        guard let index = document.entries.firstIndex(where: { $0.id == original.id }) else { throw FoodDraftError.missingEntry }
        guard document.entries[index] == original else { throw FoodDraftError.changedEntry }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, amount.isFinite, amount > 0,
              !items.isEmpty, items.allSatisfy({ $0.amount.isFinite && $0.amount > 0 }) else { throw FoodDraftError.invalidDraft }
        if amount != original.amount || items != original.mealItems {
            updateMealEntry(entryID: original.id, amount: amount, items: items, allowCheatDay: true)
        }
        document.entries[index].food.name = name
        document.entries[index].processedMeatOverride = processed
        document.entries[index].redMeatOverride = red
    }

    func updateEntry(
        entryID: UUID,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil,
        allowCheatDay: Bool = false
    ) {
        guard
            let index = document.entries.firstIndex(where: { $0.id == entryID }),
            !document.entries[index].isMeal,
            !document.entries[index].isCheatDayAdjustment,
            allowCheatDay || canLogFood(on: document.entries[index].date)
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
    }

    func updateEntryMeatClassification(entryID: UUID, processed: Bool?, red: Bool?) {
        guard let index = document.entries.firstIndex(where: { $0.id == entryID }),
            !document.entries[index].isCheatDayAdjustment
        else { return }

        // Once a saved-meal log receives a direct correction, retain it as this
        // diary entry's snapshot so later template edits cannot replace the choice.
        if document.entries[index].isMeal {
            document.entries[index].savedMealID = nil
        }
        document.entries[index].processedMeatOverride = processed
        document.entries[index].redMeatOverride = red
    }

    func updateMeatServingsOverride(contributions: [MeatDayFoodContribution], servings: Double?) {
        guard servings.map({ $0.isFinite && $0 >= 0 }) ?? true,
            !contributions.isEmpty,
            contributions.allSatisfy({ contribution in
                guard let entry = document.entries.first(where: { $0.id == contribution.entryID }),
                    !entry.isCheatDayAdjustment
                else { return false }
                guard let mealItemID = contribution.mealItemID else { return true }
                return entry.mealItems?.contains(where: { $0.id == mealItemID }) == true
            })
        else { return }

        let calculatedTotal = contributions.reduce(0) { $0 + $1.calculatedServings }
        for contribution in contributions {
            let contributionOverride: Double?
            if let servings {
                contributionOverride = calculatedTotal > 0
                    ? servings * contribution.calculatedServings / calculatedTotal
                    : servings / Double(contributions.count)
            } else {
                contributionOverride = nil
            }
            guard let entryIndex = document.entries.firstIndex(where: { $0.id == contribution.entryID }) else { continue }
            if let mealItemID = contribution.mealItemID {
                guard var items = document.entries[entryIndex].mealItems,
                    let itemIndex = items.firstIndex(where: { $0.id == mealItemID })
                else { continue }
                items[itemIndex].meatServingsOverride = contributionOverride
                document.entries[entryIndex].mealItems = items
            } else {
                document.entries[entryIndex].meatServingsOverride = contributionOverride
            }
        }
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
    }

    func moveEntry(_ entryID: UUID, toIndex destinationIndex: Int, on date: Date) {
        var orderedEntries = entries(on: date)
        guard let sourceIndex = orderedEntries.firstIndex(where: { $0.id == entryID }) else { return }

        let movedEntry = orderedEntries.remove(at: sourceIndex)
        let boundedDestination = min(max(destinationIndex, 0), orderedEntries.count)
        orderedEntries.insert(movedEntry, at: boundedDestination)
        updateDisplayOrder(using: orderedEntries)
    }

    func preference(for food: Food) -> QuantityPreference {
        if let remembered = document.rememberedQuantities[food.id] {
            return remembered
        }
        if let naturalPortion = NaturalFoodPortionHeuristics.preferredPortion(for: food) {
            return QuantityPreference(amount: 1, unit: .serving, portionID: naturalPortion.id)
        }
        let rawUnit = LoggingPreferences.lastWeightUnit.rawValue
        let unit = LogUnit(rawValue: rawUnit) ?? .ounces
        return QuantityPreference(amount: unit == .ounces ? 1 : 100, unit: unit)
    }

    func rememberLastWeightUnit(_ unit: LogUnit) {
        guard unit == .ounces || unit == .grams else { return }
        LoggingPreferences.lastWeightUnit = unit
    }

    func rememberPreference(_ preference: QuantityPreference, for food: Food) {
        document.rememberedQuantities[food.id] = QuantityPreference(
            amount: max(preference.amount, 0.01),
            unit: preference.unit,
            portionID: preference.portionID
        )
    }

    func quickLog(_ food: Food, on date: Date, allowCheatDay: Bool = false) {
        let preference = preference(for: food)
        log(
            food,
            amount: preference.amount,
            unit: preference.unit,
            portionID: preference.portionID,
            on: date,
            allowCheatDay: allowCheatDay
        )
    }

    @discardableResult
    func logMagicSuggestion(_ suggestion: MagicFoodSuggestion, on date: Date) -> [FoodPickerItem] {
        guard canLogFood(on: date) else { return [] }
        var loggedItems: [FoodPickerItem] = []
        for item in suggestion.items {
            let previousEntryCount = entries(on: date).count
            switch item {
            case .food(let food):
                quickLog(food, on: date)
            case .meal(let meal):
                logMeal(meal, on: date)
            }
            if entries(on: date).count > previousEntryCount {
                loggedItems.append(item)
            }
        }
        return loggedItems
    }

    @discardableResult
    func logQuickSelection(_ selectionID: String, on date: Date = Date()) -> QuickLogResult? {
        let snapshot = QuickLogSnapshot(document: document, calendar: calendar)
        guard let selection = snapshot.selection(id: selectionID), canLogFood(on: date) else {
            return nil
        }

        let original = document
        var loggedCount = 0
        for itemID in selection.itemIDs {
            guard let item = snapshot.item(id: itemID) else { continue }
            let previousEntryCount = entries(on: date).count
            switch item {
            case .food(let food):
                quickLog(food, on: date)
            case .meal(let meal):
                logMeal(meal, on: date)
            }
            if entries(on: date).count > previousEntryCount {
                loggedCount += 1
            }
        }

        guard loggedCount == selection.itemIDs.count else {
            document = original
            return nil
        }
        return QuickLogResult(title: selection.title, loggedItemCount: loggedCount, selectionID: selectionID)
    }

    func isFavorite(_ food: Food) -> Bool {
        document.favorites.contains { $0.id == food.id }
    }

    func toggleFavorite(_ food: Food, preference: QuantityPreference? = nil) {
        if let index = document.favorites.firstIndex(where: { $0.id == food.id }) {
            document.favorites.remove(at: index)
            removeFavoriteOrder(for: "food:\(food.id)")
        } else {
            document.favorites.insert(displayedFood(food), at: 0)
            if let preference {
                document.rememberedQuantities[food.id] = preference
            }
            insertFavoriteOrder(for: "food:\(food.id)")
        }
    }

    var favoriteMeals: [SavedMeal] {
        document.favoriteMealIDs.compactMap { mealID in
            document.meals.first { $0.id == mealID }
        }
    }

    var favoriteItems: [FoodPickerItem] {
        interspersedItems(
            foods: document.favorites,
            meals: favoriteMeals
        ).sorted {
            let leftName = favoriteItemName($0)
            let rightName = favoriteItemName($1)
            let comparison = leftName.localizedCaseInsensitiveCompare(rightName)
            if comparison == .orderedSame {
                return $0.id < $1.id
            }
            return comparison == .orderedAscending
        }
    }

    func isFavorite(_ meal: SavedMeal) -> Bool {
        document.favoriteMealIDs.contains(meal.id)
    }

    func toggleFavorite(_ meal: SavedMeal) {
        guard document.meals.contains(where: { $0.id == meal.id }) else { return }
        if let index = document.favoriteMealIDs.firstIndex(of: meal.id) {
            document.favoriteMealIDs.remove(at: index)
            removeFavoriteOrder(for: "meal:\(meal.id.uuidString)")
        } else {
            document.favoriteMealIDs.insert(meal.id, at: 0)
            insertFavoriteOrder(for: "meal:\(meal.id.uuidString)")
        }
    }

    var alphabetizedMeals: [SavedMeal] {
        document.meals.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison == .orderedSame {
                return $0.id.uuidString < $1.id.uuidString
            }
            return comparison == .orderedAscending
        }
    }

    /// Hand-created meals shown in Personal Library.
    var customMeals: [SavedMeal] {
        alphabetizedMeals.filter { !$0.isImported }
    }

    /// Imported meal snapshots shown in the Log Food meal picker.
    var importedMeals: [SavedMeal] {
        alphabetizedMeals.filter(\.isImported)
    }

    var recentFoods: [Food] {
        uniqueFoods(
            from: document.entries.filter { !$0.isMeal && !$0.isCheatDayAdjustment }
                .sorted { $0.loggedAt > $1.loggedAt },
            limit: 30
        )
    }

    var recentItems: [FoodPickerItem] {
        var seen = Set<String>()
        return document.entries
            .filter { !$0.isCheatDayAdjustment }
            .sorted { $0.loggedAt > $1.loggedAt }
            .compactMap { entry -> FoodPickerItem? in
                guard let item = pickerItem(for: entry), seen.insert(item.id).inserted else {
                    return nil
                }
                return item
            }
            .prefix(30)
            .map { $0 }
    }

    var frequentFoods: [Food] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let recentEntries = document.entries.filter {
            $0.date >= cutoff && !$0.isMeal && !$0.isCheatDayAdjustment
        }
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
            .map(displayedFood)
    }

    var frequentItems: [FoodPickerItem] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let recentEntries = document.entries.filter { $0.date >= cutoff && !$0.isCheatDayAdjustment }
        let grouped = Dictionary(grouping: recentEntries, by: pickerItemKey(for:))

        return grouped.values
            .compactMap { entries -> (item: FoodPickerItem, count: Int, latest: Date)? in
                guard
                    let latestEntry = entries.max(by: { $0.loggedAt < $1.loggedAt }),
                    let item = pickerItem(for: latestEntry)
                else { return nil }
                return (item, entries.count, latestEntry.loggedAt)
            }
            .sorted {
                if $0.count == $1.count { return $0.latest > $1.latest }
                return $0.count > $1.count
            }
            .prefix(30)
            .map(\.item)
    }

    func magicSuggestions(
        at referenceDate: Date = Date(),
        lookbackDays: Int = 10,
        limit: Int = 4
    ) -> [MagicFoodSuggestion] {
        magicSuggestionResult(
            at: referenceDate,
            lookbackDays: lookbackDays,
            limit: limit
        ).suggestions
    }

    func magicSuggestionResult(
        at referenceDate: Date = Date(),
        lookbackDays: Int = 10,
        limit: Int = 4
    ) -> MagicFoodSuggestionResult {
        QuickLogSnapshot(document: document, calendar: calendar).magicSuggestionResult(
            at: referenceDate, lookbackDays: lookbackDays, limit: limit
        )
    }

    func addCustomFood(
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil,
        servingGrams: Double,
        servingDescription: String = "1 serving",
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil
    ) -> Food {
        let normalizedServingDescription =
            servingDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let portionLabel = normalizedServingDescription.replacingOccurrences(
            of: #"^1\s+"#,
            with: "",
            options: .regularExpression
        )
        let food = Food(
            sourceID: UUID().uuidString,
            source: .custom,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            barcode: nil,
            nutrients: MacroNutrients(
                calories: calories,
                carbs: carbs,
                fat: fat,
                protein: protein,
                fiber: fiber
            ),
            baseAmountGrams: max(servingGrams, 0.01),
            servingGrams: max(servingGrams, 0.01),
            servingDescription: normalizedServingDescription.isEmpty ? "1 serving" : normalizedServingDescription,
            portions: [
                FoodPortion(
                    id: "custom-serving",
                    label: portionLabel.isEmpty ? "serving" : portionLabel,
                    grams: max(servingGrams, 0.01)
                )
            ],
            containsProcessedMeat: containsProcessedMeat,
            containsRedMeat: containsRedMeat
        )
        let resolved = FoodResolver(catalog: catalog).applying(
            FoodMeatOverrides(processed: containsProcessedMeat, red: containsRedMeat), to: food)
        document.customFoods.insert(resolved, at: 0)
        return resolved
    }

    @discardableResult
    func updateCustomFood(
        foodID: String,
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil,
        servingGrams: Double,
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        meatOverrides: FoodMeatOverrides? = nil
    ) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedServingGrams = max(servingGrams, 0.01)
        guard !normalizedName.isEmpty,
            let customFoodIndex = document.customFoods.firstIndex(where: { $0.id == foodID })
        else { return false }

        var updatedFood = document.customFoods[customFoodIndex]
        updatedFood.name = normalizedName
        updatedFood.brand = normalizedBrand
        updatedFood.nutrients = MacroNutrients(
            calories: calories,
            carbs: carbs,
            fat: fat,
            protein: protein,
            fiber: fiber
        )
        updatedFood.baseAmountGrams = normalizedServingGrams
        updatedFood.servingGrams = normalizedServingGrams
        updatedFood.servingDescription = "1 serving"
        updatedFood.portions = [
            FoodPortion(
                id: "custom-serving",
                label: "serving",
                grams: normalizedServingGrams
            )
        ]
        if let meatOverrides {
            updatedFood = FoodResolver(catalog: catalog).applying(meatOverrides, to: updatedFood)
        } else if containsProcessedMeat != nil || containsRedMeat != nil {
            var provenance = updatedFood.meatResolution ?? FoodMeatResolution(
                processed: .legacy, red: .legacy, inputName: updatedFood.name)
            if let containsProcessedMeat {
                updatedFood.containsProcessedMeat = containsProcessedMeat
                provenance.processed = .user
            }
            if let containsRedMeat {
                updatedFood.containsRedMeat = containsRedMeat
                provenance.red = .user
            }
            updatedFood.meatResolution = provenance
        }
        updatedFood = FoodResolver(catalog: catalog).resolve(updatedFood)

        document.customFoods[customFoodIndex] = updatedFood
        document.customFoodNames.removeValue(forKey: foodID)
        document.favorites = document.favorites.map {
            $0.id == foodID ? updatedFood : $0
        }
        for index in document.meals.indices {
            document.meals[index].items = document.meals[index].items.map { item in
                guard item.food.id == foodID else { return item }
                var updatedItem = item
                updatedItem.food = updatedFood
                return updatedItem
            }
        }
        for index in document.entries.indices {
            var entry = document.entries[index]
            if entry.food.id == foodID, !entry.isMeal {
                entry.food = updatedFood
                entry.nutrients = updatedFood.nutrients(
                    for: entry.amount,
                    unit: entry.unit,
                    portionID: entry.portionID
                )
            }
            entry.mealItems = entry.mealItems?.map { item in
                guard item.food.id == foodID else { return item }
                var updatedItem = item
                updatedItem.food = updatedFood
                return updatedItem
            }
            refreshMealEntry(&entry)
            document.entries[index] = entry
        }
        return true
    }

    @discardableResult
    func saveMeal(
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        origin: SavedMealOrigin = .custom
    ) -> SavedMeal? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !items.isEmpty else { return nil }
        let meal = SavedMeal(
            id: UUID(),
            name: normalizedName,
            items: resolvedItems(items),
            containsProcessedMeat: containsProcessedMeat,
            containsRedMeat: containsRedMeat,
            origin: origin
        )
        document.meals.insert(meal, at: 0)
        return meal
    }

    @discardableResult
    func updateSavedMeal(
        mealID: UUID,
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        meatOverrides: FoodMeatOverrides? = nil
    ) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
            !items.isEmpty,
            let mealIndex = document.meals.firstIndex(where: { $0.id == mealID })
        else { return false }

        let previousMeal = document.meals[mealIndex]
        document.meals[mealIndex] = SavedMeal(
            id: mealID,
            name: normalizedName,
            items: resolvedItems(items),
            containsProcessedMeat: meatOverrides.map(\.processed) ?? (containsProcessedMeat ?? previousMeal.containsProcessedMeat),
            containsRedMeat: meatOverrides.map(\.red) ?? (containsRedMeat ?? previousMeal.containsRedMeat),
            origin: previousMeal.origin, notes: previousMeal.notes
        )
        for index in document.entries.indices where document.entries[index].savedMealID == mealID {
            var entry = document.entries[index]
            entry.food.name = normalizedName
            refreshMealEntry(&entry)
            document.entries[index] = entry
        }
        return true
    }

    func saveMeal(name: String, replacing entryIDs: Set<UUID>, on date: Date) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !entryIDs.isEmpty, canLogFood(on: date) else { return }

        let dayEntries = entries(on: date)
        let selectedEntries = dayEntries.filter {
            entryIDs.contains($0.id) && !$0.isCheatDayAdjustment
        }
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
                    portionID: $0.portionID,
                    meatServingsOverride: $0.meatServingsOverride,
                    foodConfigurationSnapshot: $0.foodConfigurationSnapshot,
                    processedMeatOverride: $0.processedMeatOverride, redMeatOverride: $0.redMeatOverride
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
    }

    func breakApartMeal(entryID: UUID) {
        guard
            let mealEntry = document.entries.first(where: { $0.id == entryID }),
            mealEntry.isMeal,
            canLogFood(on: mealEntry.date)
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
                portionID: $0.portionID,
                processedMeatOverride: $0.processedMeatOverride, redMeatOverride: $0.redMeatOverride,
                meatServingsOverride: $0.meatServingsOverride, foodConfigurationSnapshot: $0.foodConfigurationSnapshot
            )
        }
        dayEntries.insert(contentsOf: expandedEntries, at: mealIndex)

        document.entries.removeAll { calendar.isDate($0.date, inSameDayAs: mealEntry.date) }
        for (displayOrder, var entry) in dayEntries.enumerated() {
            entry.displayOrder = displayOrder
            document.entries.append(entry)
        }
    }

    func deleteCustomFood(_ food: Food) {
        document.customFoods.removeAll { $0.id == food.id }
        document.favorites.removeAll { $0.id == food.id }
        removeFavoriteOrder(for: "food:\(food.id)")
        document.rememberedQuantities.removeValue(forKey: food.id)
    }

    func deleteMeal(_ meal: SavedMeal) {
        document.meals.removeAll { $0.id == meal.id }
        document.favoriteMealIDs.removeAll { $0 == meal.id }
        removeFavoriteOrder(for: "meal:\(meal.id.uuidString)")
    }

    func logMeal(
        _ meal: SavedMeal,
        amount: Double = 1,
        on date: Date,
        allowCheatDay: Bool = false
    ) {
        let meal = document.meals.first { $0.id == meal.id } ?? meal
        guard !meal.items.isEmpty, amount > 0, allowCheatDay || canLogFood(on: date) else { return }
        clearAutomaticStatus(on: date)
        let entry = makeMealEntry(
            for: meal,
            amount: amount,
            on: date,
            loggedAt: Date(),
            displayOrder: nextDisplayOrder(on: date)
        )
        document.entries.append(entry)
    }

    func logOneOffMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date, allowCheatDay: Bool = false) {
        guard !meal.items.isEmpty, amount > 0, allowCheatDay || canLogFood(on: date) else { return }
        clearAutomaticStatus(on: date)
        var entry = makeMealEntry(
            for: meal,
            amount: amount,
            on: date,
            loggedAt: Date(),
            displayOrder: nextDisplayOrder(on: date)
        )
        entry.savedMealID = nil
        document.entries.append(entry)
    }

    func updateMealEntry(entryID: UUID, amount: Double, allowCheatDay: Bool = false) {
        guard
            let index = document.entries.firstIndex(where: { $0.id == entryID }),
            document.entries[index].isMeal,
            amount > 0,
            allowCheatDay || canLogFood(on: document.entries[index].date)
        else { return }

        let entry = document.entries[index]
        let clampedAmount = max(amount, 0.01)
        let baseItems: [MealItem]
        if let savedMealID = entry.savedMealID,
            let savedMeal = document.meals.first(where: { $0.id == savedMealID })
        {
            baseItems = savedMeal.items
        } else if let currentItems = entry.mealItems, entry.amount > 0 {
            baseItems = currentItems.map { item in
                var baseItem = item
                baseItem.amount /= entry.amount
                return baseItem
            }
        } else {
            return
        }

        let baseNutrients = baseItems.reduce(.zero) { total, item in
            total
                + item.food.nutrients(
                    for: item.amount,
                    unit: item.unit,
                    portionID: item.portionID
                )
        }
        let scaledItems = baseItems.map { item in
            var scaledItem = item
            scaledItem.amount *= clampedAmount
            return scaledItem
        }

        document.entries[index].amount = clampedAmount
        document.entries[index].unit = .serving
        document.entries[index].portionID = "saved-meal"
        document.entries[index].food.nutrients = baseNutrients
        document.entries[index].nutrients = baseNutrients.scaled(by: clampedAmount)
        document.entries[index].mealItems = scaledItems
    }

    /// Updates the ingredients for one logged meal without changing the saved meal template.
    /// The logged entry becomes a snapshot so later edits to the saved meal do not overwrite
    /// this intentional per-entry adjustment.
    func updateMealEntry(
        entryID: UUID,
        amount: Double,
        items: [MealItem],
        allowCheatDay: Bool = false
    ) {
        let items = resolvedItems(items)
        guard
            let index = document.entries.firstIndex(where: { $0.id == entryID }),
            document.entries[index].isMeal,
            amount > 0,
            !items.isEmpty,
            items.allSatisfy({ $0.amount.isFinite && $0.amount > 0 }),
            allowCheatDay || canLogFood(on: document.entries[index].date)
        else { return }

        let clampedAmount = max(amount, 0.01)
        let baseItems = items.map { item in
            var baseItem = item
            baseItem.amount /= clampedAmount
            return baseItem
        }
        let baseNutrients = baseItems.reduce(.zero) { total, item in
            total
                + item.food.nutrients(
                    for: item.amount,
                    unit: item.unit,
                    portionID: item.portionID
                )
        }

        document.entries[index].savedMealID = nil
        document.entries[index].amount = clampedAmount
        document.entries[index].unit = .serving
        document.entries[index].portionID = "saved-meal"
        document.entries[index].food.nutrients = baseNutrients
        document.entries[index].nutrients = baseNutrients.scaled(by: clampedAmount)
        document.entries[index].mealItems = items
        let classification = entryMeatClassification(document.entries[index])
        document.entries[index].food.containsProcessedMeat = classification.containsProcessedMeat
        document.entries[index].food.containsRedMeat = classification.containsRedMeat
    }

    @discardableResult
    func renameMeal(mealID: UUID, name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
            document.meals.contains(where: { $0.id == mealID })
        else { return false }

        for index in document.meals.indices where document.meals[index].id == mealID {
            document.meals[index].name = normalizedName
        }
        for index in document.entries.indices where document.entries[index].savedMealID == mealID {
            document.entries[index].food.name = normalizedName
        }
        return true
    }

    func searchPersonalFoods(_ query: String) -> [Food] {
        let all = personalFoods
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return Array(all.prefix(50)) }
        return all.filter {
            $0.name.localizedStandardContains(normalized)
                || (document.customFoodNames[$0.id]?.localizedStandardContains(normalized) ?? false)
                || ($0.brand?.localizedStandardContains(normalized) ?? false)
        }.prefix(50).map { $0 }
    }

    func searchItems(_ query: String, catalogFoods: [Food], limit: Int = 50) -> [FoodPickerItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        let matchingFavoriteFoods = document.favorites
            .filter { matchesSearch($0, query: normalized) }
            .map(displayedFood)
        let matchingMeals = document.meals.filter {
            $0.name.localizedStandardContains(normalized)
        }
        let prioritizedItems = interspersedItems(
            foods: matchingFavoriteFoods,
            meals: matchingMeals
        ).sorted(by: searchItemAlphabeticalOrder)

        let personalResults = searchPersonalFoods(normalized)
        let queryTokenCount = normalized
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .count
        let canonicalFirstBroadSearch = catalog?.activeRankingVersion == .canonicalFirst
            && queryTokenCount == 1
        let fallbackItems = Array(personalResults.prefix(10))
            + catalogFoods
            + Array(personalResults.dropFirst(10))

        var seen = Set<String>()
        let orderedItems: [FoodPickerItem]
        if canonicalFirstBroadSearch {
            let canonicalLead = Array(catalogFoods.prefix(3)).map { FoodPickerItem.food(displayedFood($0)) }
            let remainingCatalog = Array(catalogFoods.dropFirst(3)).map { FoodPickerItem.food(displayedFood($0)) }
            orderedItems = canonicalLead
                + prioritizedItems
                + personalResults.map { .food(displayedFood($0)) }
                + remainingCatalog
        } else {
            orderedItems = prioritizedItems + fallbackItems.map { .food(displayedFood($0)) }
        }
        return orderedItems
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }

    func displayedFood(_ food: Food) -> Food {
        var displayedFood = food
        if displayedFood.nutrients.fiber == nil,
            displayedFood.source != .custom,
            let fiber = catalog?.fiber(
                sourceID: displayedFood.sourceID,
                source: displayedFood.source
            )
        {
            displayedFood.nutrients.fiber = fiber
        }
        if let customName = document.customFoodNames[food.id], !customName.isEmpty {
            displayedFood.name = customName
        }
        let resolved = FoodResolver(catalog: catalog).resolve(displayedFood)
        guard let identity = FoodCatalogIdentity(food: resolved),
              let overrides = document.corpusFoodMeatOverrides[identity]
        else { return resolved }
        return FoodResolver(catalog: catalog).applying(overrides, to: resolved)
    }

    func corpusFoodMeatOverrides(for food: Food) -> FoodMeatOverrides {
        FoodCatalogIdentity(food: food).flatMap { document.corpusFoodMeatOverrides[$0] }
            ?? FoodMeatOverrides(processed: nil, red: nil)
    }

    /// An explicit correction of one corpus identity. The original snapshot must still exist in
    /// the transaction snapshot, and every matching reference changes without touching nutrition.
    func updateCorpusFoodMeatTags(originalFood: Food, overrides: FoodMeatOverrides) throws {
        guard let identity = FoodCatalogIdentity(food: originalFood) else {
            throw DiaryDatabaseError.invalidData("Only USDA and Open Food Facts foods can be corrected here.")
        }

        let snapshots = document.customFoods + document.favorites + document.meals.flatMap { $0.items.map(\.food) }
            + document.entries.flatMap { entry in
                entry.isMeal ? (entry.mealItems ?? []).map(\.food) : [entry.food]
            }
        let identitySnapshots = snapshots.filter { FoodCatalogIdentity(food: $0) == identity }
        let isCurrentSnapshot = identitySnapshots.contains(where: { $0 == originalFood })
        let isUnreferencedCatalogFood = identitySnapshots.isEmpty
            && catalog?.food(sourceID: identity.sourceID, source: identity.source) != nil
        guard isCurrentSnapshot || isUnreferencedCatalogFood else {
            throw DiaryDatabaseError.invalidData("This food changed since it was opened. Reload it before correcting its classification.")
        }

        if overrides.processed == nil && overrides.red == nil {
            document.corpusFoodMeatOverrides.removeValue(forKey: identity)
        } else {
            document.corpusFoodMeatOverrides[identity] = overrides
        }

        func corrected(_ food: Food) -> Food {
            guard FoodCatalogIdentity(food: food) == identity else { return food }
            return FoodResolver(catalog: catalog).applying(overrides, to: food)
        }
        func correctedItems(_ items: [MealItem]) -> [MealItem] {
            items.map { item in
                var result = item
                result.food = corrected(item.food)
                return result
            }
        }

        document.customFoods = document.customFoods.map(corrected)
        document.favorites = document.favorites.map(corrected)
        document.meals = document.meals.map { meal in
            var result = meal
            result.items = correctedItems(meal.items)
            return result
        }
        for index in document.entries.indices {
            var entry = document.entries[index]
            if entry.isMeal, let mealItems = entry.mealItems {
                entry.mealItems = correctedItems(mealItems)
                let classification = entryMeatClassification(entry)
                entry.food.containsProcessedMeat = classification.containsProcessedMeat
                entry.food.containsRedMeat = classification.containsRedMeat
            } else {
                entry.food = corrected(entry.food)
            }
            document.entries[index] = entry
        }
    }

    @discardableResult
    func renameFood(foodID: String, name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return false }

        // The rename mutates nested values inside the published document.
        // Announce it explicitly so SwiftUI refreshes the diary immediately.
        document.customFoodNames[foodID] = normalizedName

        for index in document.entries.indices {
            if document.entries[index].food.id == foodID {
                document.entries[index].food.name = normalizedName
            }
            document.entries[index].mealItems = document.entries[index].mealItems?.map {
                var item = $0
                if item.food.id == foodID {
                    item.food.name = normalizedName
                }
                return item
            }
        }

        document.favorites = document.favorites.map { renamedFood($0, foodID: foodID, name: normalizedName) }
        document.customFoods = document.customFoods.map { renamedFood($0, foodID: foodID, name: normalizedName) }
        document.meals = document.meals.map { meal in
            var updatedMeal = meal
            updatedMeal.items = meal.items.map { item in
                var updatedItem = item
                updatedItem.food = renamedFood(item.food, foodID: foodID, name: normalizedName)
                return updatedItem
            }
            return updatedMeal
        }
        return true
    }

    func clearPersonalData() {
        clearsPersonalData = true
        document = DiaryDocument()
        document.trackingStartDate = calendar.startOfDay(for: Date())
    }

    func totalsByDay(numberOfDays: Int = 30) -> [(date: Date, nutrients: MacroNutrients)] {
        let today = calendar.startOfDay(for: Date())
        return (0..<numberOfDays).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, totals(on: date))
        }
    }

    private func reconcileAutomaticStatus(on date: Date) {
        let day = calendar.startOfDay(for: date)
        if let existing = status(on: day), existing.source == .manual {
            return
        }

        document.dayStatuses.removeAll {
            calendar.isDate($0.date, inSameDayAs: day) && $0.source == .automatic
        }
        guard hasTrackedData(on: day) else {
            upsertStatus(DayStatus(date: day, kind: .gap, source: .automatic))
            return
        }

        guard let goal = dailyCalorieGoal, goal > 0 else { return }
        let ratio = totals(on: day).calories / Double(goal)
        if ratio < 0.75 || ratio > 1.30 {
            upsertStatus(DayStatus(date: day, kind: .cheat, source: .automatic))
        }
    }

    private func upsertStatus(_ status: DayStatus) {
        document.dayStatuses.removeAll {
            calendar.isDate($0.date, inSameDayAs: status.date)
        }
        document.dayStatuses.append(status)
        document.dayStatuses.sort { $0.date < $1.date }
    }

    private func clearAutomaticStatus(on date: Date) {
        document.dayStatuses.removeAll {
            calendar.isDate($0.date, inSameDayAs: date) && $0.source == .automatic
        }
    }

    private func hasTrackedData(on date: Date) -> Bool {
        !entries(on: date).isEmpty || alcoholDrinkCount(on: date) > 0
    }

    private func hasLoggedFoodOrMeal(on date: Date) -> Bool {
        entries(on: date).contains { !$0.isCheatDayAdjustment }
    }

    private func makeCalorieAdjustment(calories: Int, on date: Date) -> DiaryEntry {
        let food = Food(
            sourceID: "calorie-adjustment",
            source: .custom,
            name: "Calorie adjustment",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(
                calories: Double(calories),
                carbs: 0,
                fat: 0,
                protein: 0,
                fiber: 0
            ),
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 adjustment",
            portions: [FoodPortion(id: "calorie-adjustment", label: "adjustment", grams: 1)]
        )
        return DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date),
            food: food,
            amount: 1,
            unit: .serving,
            nutrients: food.nutrients,
            loggedAt: Date(),
            portionID: "calorie-adjustment",
            displayOrder: nextDisplayOrder(on: date),
            kind: .cheatDayAdjustment
        )
    }

    private func makeAlcoholHealthEntry(_ alcohol: AlcoholEntry) -> DiaryEntry {
        let perDrinkNutrients = MacroNutrients(
            calories: Double(alcohol.caloriesPerDrink),
            carbs: 0,
            fat: 0,
            protein: 0,
            fiber: 0
        )
        let food = Food(
            sourceID: "alcohol-\(alcohol.type?.rawValue ?? "default")",
            source: .custom,
            name: alcohol.type?.title ?? "Alcohol",
            brand: nil,
            barcode: nil,
            nutrients: perDrinkNutrients,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 drink",
            portions: [FoodPortion(id: "alcohol-drink", label: "drink", grams: 1)]
        )
        return DiaryEntry(
            id: alcohol.id,
            date: calendar.startOfDay(for: alcohol.date),
            food: food,
            amount: Double(alcohol.drinks),
            unit: .serving,
            nutrients: alcohol.nutrients,
            loggedAt: alcohol.loggedAt,
            portionID: "alcohol-drink"
        )
    }

    private func frequentFoods(on dates: Set<Date>) -> [FrequentFood] {
        let entries = document.entries.filter {
            !$0.isCheatDayAdjustment && dates.contains(calendar.startOfDay(for: $0.date))
        }
        let grouped = Dictionary(grouping: entries, by: { $0.food.name })
        return
            grouped
            .map { FrequentFood(name: $0.key, count: $0.value.count) }
            .sorted { left, right in
                if left.count == right.count {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.count > right.count
            }
            .prefix(5)
            .map { $0 }
    }

    private func uniqueFoods(from entries: [DiaryEntry], limit: Int) -> [Food] {
        var seen = Set<String>()
        var foods: [Food] = []
        for entry in entries where seen.insert(entry.food.id).inserted {
            foods.append(displayedFood(entry.food))
            if foods.count == limit { break }
        }
        return foods
    }

    private func combinations<T>(of items: [T], choosing count: Int) -> [[T]] {
        guard count > 0, count <= items.count else { return [] }
        if count == 1 { return items.map { [$0] } }
        if count == items.count { return [items] }

        var result: [[T]] = []
        for index in 0...(items.count - count) {
            let head = items[index]
            let tail = Array(items[(index + 1)...])
            result.append(contentsOf: combinations(of: tail, choosing: count - 1).map { [head] + $0 })
        }
        return result
    }

    private func pickerItem(for entry: DiaryEntry) -> FoodPickerItem? {
        if entry.isMeal {
            guard
                let savedMealID = entry.savedMealID,
                let meal = document.meals.first(where: { $0.id == savedMealID })
            else { return nil }
            return .meal(meal)
        }
        return .food(displayedFood(entry.food))
    }

    private func pickerItemKey(for entry: DiaryEntry) -> String {
        if let savedMealID = entry.savedMealID {
            return "meal:\(savedMealID.uuidString)"
        }
        return "food:\(entry.food.id)"
    }

    private func interspersedItems(foods: [Food], meals: [SavedMeal]) -> [FoodPickerItem] {
        var items: [FoodPickerItem] = []
        var foodIndex = 0
        var mealIndex = 0

        while foodIndex < foods.count || mealIndex < meals.count {
            if foodIndex < foods.count {
                items.append(.food(displayedFood(foods[foodIndex])))
                foodIndex += 1
            }
            if mealIndex < meals.count {
                items.append(.meal(meals[mealIndex]))
                mealIndex += 1
            }
        }
        return items
    }

    private func favoriteItemName(_ item: FoodPickerItem) -> String {
        switch item {
        case .food(let food): food.name
        case .meal(let meal): meal.name
        }
    }

    private func searchItemAlphabeticalOrder(_ left: FoodPickerItem, _ right: FoodPickerItem) -> Bool {
        let comparison = favoriteItemName(left).localizedCaseInsensitiveCompare(favoriteItemName(right))
        if comparison == .orderedSame {
            return left.id < right.id
        }
        return comparison == .orderedAscending
    }

    private func matchesSearch(_ food: Food, query: String) -> Bool {
        food.name.localizedStandardContains(query)
            || (document.customFoodNames[food.id]?.localizedStandardContains(query) ?? false)
            || (food.brand?.localizedStandardContains(query) ?? false)
    }

    private func insertFavoriteOrder(for itemID: String) {
        if document.favoriteItemOrder.isEmpty {
            document.favoriteItemOrder = interspersedItems(
                foods: document.favorites,
                meals: favoriteMeals
            ).map(\.id).filter { $0 != itemID }
        } else {
            document.favoriteItemOrder.removeAll { $0 == itemID }
        }
        document.favoriteItemOrder.insert(itemID, at: 0)
    }

    private func removeFavoriteOrder(for itemID: String) {
        document.favoriteItemOrder.removeAll { $0 == itemID }
    }

    private var personalFoods: [Food] {
        var seen = Set<String>()
        let candidates =
            document.entries
            .filter { !$0.isMeal && !$0.isCheatDayAdjustment }
            .sorted { $0.loggedAt > $1.loggedAt }
            .map(\.food) + document.favorites + document.customFoods
        return candidates.compactMap { food in
            guard seen.insert(food.id).inserted else { return nil }
            return displayedFood(food)
        }
    }

    private func renamedFood(_ food: Food, foodID: String, name: String) -> Food {
        guard food.id == foodID else { return food }
        var renamed = food
        renamed.name = name
        return renamed
    }

    private func nextDisplayOrder(on date: Date) -> Int {
        let firstOrder =
            document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .compactMap(\.displayOrder)
            .min() ?? 0
        return firstOrder - 1
    }

    private func refreshMealEntry(_ entry: inout DiaryEntry) {
        guard entry.isMeal else { return }
        let baseItems: [MealItem]
        let classification: MeatClassification
        if let savedMealID = entry.savedMealID,
            let savedMeal = document.meals.first(where: { $0.id == savedMealID })
        {
            baseItems = savedMeal.items
            entry.food.name = savedMeal.name
            entry.processedMeatOverride = savedMeal.containsProcessedMeat
            entry.redMeatOverride = savedMeal.containsRedMeat
            classification = MeatClassification(
                containsProcessedMeat: savedMeal.resolvedContainsProcessedMeat,
                containsRedMeat: savedMeal.resolvedContainsRedMeat
            )
        } else if let currentItems = entry.mealItems, entry.amount > 0 {
            baseItems = currentItems.map { item in
                var baseItem = item
                baseItem.amount /= entry.amount
                return baseItem
            }
            classification = entryMeatClassification(entry)
        } else {
            return
        }

        let baseNutrients = baseItems.reduce(.zero) { total, item in
            total
                + item.food.nutrients(
                    for: item.amount,
                    unit: item.unit,
                    portionID: item.portionID
                )
        }
        entry.food.nutrients = baseNutrients
        entry.food.containsProcessedMeat = classification.containsProcessedMeat
        entry.food.containsRedMeat = classification.containsRedMeat
        entry.nutrients = baseNutrients.scaled(by: max(entry.amount, 0.01))
        entry.mealItems = baseItems.map { item in
            var scaledItem = item
            scaledItem.amount *= max(entry.amount, 0.01)
            return scaledItem
        }
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
        amount: Double = 1,
        on date: Date,
        loggedAt: Date,
        displayOrder: Int? = nil
    ) -> DiaryEntry {
        var meal = meal
        meal.items = resolvedItems(meal.items)
        let clampedAmount = max(amount, 0.01)
        let scaledItems = meal.items.map { item in
            var scaledItem = item
            scaledItem.amount *= clampedAmount
            return scaledItem
        }
        let baseNutrients = meal.nutrients
        let mealFood = Food(
            sourceID: "saved-meal-\(meal.id.uuidString)",
            source: .custom,
            name: meal.name,
            brand: nil,
            barcode: nil,
            nutrients: baseNutrients,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 meal",
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)],
            containsProcessedMeat: meal.resolvedContainsProcessedMeat,
            containsRedMeat: meal.resolvedContainsRedMeat
        )
        return DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date),
            food: mealFood,
            amount: clampedAmount,
            unit: .serving,
            nutrients: baseNutrients.scaled(by: clampedAmount),
            loggedAt: loggedAt,
            portionID: "saved-meal",
            displayOrder: displayOrder,
            savedMealID: meal.id,
            mealItems: scaledItems,
            processedMeatOverride: meal.containsProcessedMeat,
            redMeatOverride: meal.containsRedMeat,
            mealNotes: meal.notes
        )
    }

    private func entryMeatClassification(_ entry: DiaryEntry) -> MeatClassification {
        guard entry.isMeal, let items = entry.mealItems else {
            let derived = Self.classification(for: entry.food)
            return MeatClassification(
                containsProcessedMeat: entry.processedMeatOverride ?? derived.containsProcessedMeat,
                containsRedMeat: entry.redMeatOverride ?? derived.containsRedMeat
            )
        }
        let derived = Self.meatClassification(for: items)
        return MeatClassification(
            containsProcessedMeat: entry.processedMeatOverride ?? derived.containsProcessedMeat,
            containsRedMeat: entry.redMeatOverride ?? derived.containsRedMeat
        )
    }

    private func mealItemMeatClassification(_ item: MealItem) -> MeatClassification {
        let derived = Self.classification(for: item.food)
        return MeatClassification(
            containsProcessedMeat: item.processedMeatOverride ?? derived.containsProcessedMeat,
            containsRedMeat: item.redMeatOverride ?? derived.containsRedMeat
        )
    }

    private func meatFoods(on date: Date) -> MeatDayFoods? {
        var processedFoods: [MeatDayFood] = []
        var redFoods: [MeatDayFood] = []

        for entry in entries(on: date) where !entry.isCheatDayAdjustment {
            let entryClassification = entryMeatClassification(entry)
            let classifiedItems = (entry.mealItems ?? []).map { item in
                let calculatedServings = servingEquivalent(
                    amount: item.amount,
                    unit: item.unit,
                    food: item.food,
                    portionID: item.portionID
                )
                return (
                    MeatDayFoodContribution(
                        entryID: entry.id,
                        mealItemID: item.id,
                        amount: item.amount,
                        unit: item.unit,
                        portionID: item.portionID,
                        calculatedServings: calculatedServings,
                        servings: item.meatServingsOverride ?? calculatedServings,
                        hasManualServingOverride: item.meatServingsOverride != nil,
                        isMealFallback: false
                    ),
                    item.food,
                    mealItemMeatClassification(item)
                )
            }

            func fallbackFood() -> MeatDayFood {
                let isMealFallback = entry.isMeal
                let calculatedServings: Double
                if isMealFallback {
                    calculatedServings = max(entry.amount, 0.01)
                } else {
                    calculatedServings = servingEquivalent(
                        amount: entry.amount,
                        unit: entry.unit,
                        food: entry.food,
                        portionID: entry.portionID
                    )
                }
                return MeatDayFood(
                    title: entry.food.name,
                    food: isMealFallback ? nil : entry.food,
                    contributions: [MeatDayFoodContribution(
                        entryID: entry.id,
                        mealItemID: nil,
                        amount: entry.amount,
                        unit: entry.unit,
                        portionID: entry.portionID,
                        calculatedServings: calculatedServings,
                        servings: entry.meatServingsOverride ?? calculatedServings,
                        hasManualServingOverride: entry.meatServingsOverride != nil,
                        isMealFallback: isMealFallback
                    )],
                    isMealFallback: isMealFallback
                )
            }

            if entryClassification.containsProcessedMeat {
                let matches =
                    classifiedItems
                    .filter { $0.2.containsProcessedMeat }
                    .map { contribution, food, _ in
                        MeatDayFood(
                            title: "\(entry.food.name) — \(food.name)",
                            food: food,
                            contributions: [contribution],
                            isMealFallback: false
                        )
                    }
                processedFoods.append(contentsOf: matches.isEmpty ? [fallbackFood()] : matches)
            }
            if entryClassification.containsRedMeat {
                let matches =
                    classifiedItems
                    .filter { $0.2.containsRedMeat }
                    .map { contribution, food, _ in
                        MeatDayFood(
                            title: "\(entry.food.name) — \(food.name)",
                            food: food,
                            contributions: [contribution],
                            isMealFallback: false
                        )
                    }
                redFoods.append(contentsOf: matches.isEmpty ? [fallbackFood()] : matches)
            }
        }

        processedFoods = Self.aggregateMeatFoods(processedFoods)
        redFoods = Self.aggregateMeatFoods(redFoods)
        guard !processedFoods.isEmpty || !redFoods.isEmpty else { return nil }
        return MeatDayFoods(
            date: calendar.startOfDay(for: date),
            processedMeatItems: processedFoods,
            redMeatItems: redFoods
        )
    }

    private static func aggregateMeatFoods(_ foods: [MeatDayFood]) -> [MeatDayFood] {
        var results: [MeatDayFood] = []
        var positions: [String: Int] = [:]
        for food in foods {
            guard let index = positions[food.id] else {
                positions[food.id] = results.count
                results.append(food)
                continue
            }
            let existing = results[index]
            results[index] = MeatDayFood(
                title: existing.title,
                food: existing.food,
                contributions: existing.contributions + food.contributions,
                isMealFallback: existing.isMealFallback
            )
        }
        return results
    }

    private static func classification(for food: Food) -> MeatClassification {
        // Unknown flags do not count as presence; resolve before persistence, not during chart rendering.
        MeatClassification(containsProcessedMeat: food.containsProcessedMeat == true,
                           containsRedMeat: food.containsRedMeat == true)
    }

    private static func meatClassification(for items: [MealItem]) -> MeatClassification {
        MeatClassification(
            containsProcessedMeat: items.contains {
                $0.processedMeatOverride ?? classification(for: $0.food).containsProcessedMeat
            },
            containsRedMeat: items.contains {
                $0.redMeatOverride ?? classification(for: $0.food).containsRedMeat
            }
        )
    }

    static func backfilledFoodMetadata(
        in source: DiaryDocument,
        catalog: CatalogStore?
    ) -> DiaryDocument {
        func enriched(_ sourceFood: Food) -> Food {
            var food = sourceFood
            if food.nutrients.fiber == nil,
                sourceFood.source != .custom,
                let fiber = catalog?.fiber(
                    sourceID: sourceFood.sourceID,
                    source: sourceFood.source
                )
            {
                food.nutrients.fiber = fiber
            }
            return FoodResolver(catalog: catalog).resolve(food)
        }

        var document = source
        document.customFoods = document.customFoods.map(enriched)
        document.favorites = document.favorites.map(enriched)
        document.meals = document.meals.map { sourceMeal in
            var meal = sourceMeal
            meal.items = meal.items.map { sourceItem in
                var item = sourceItem
                item.food = enriched(item.food)
                return item
            }
            return meal
        }
        let mealsByID = Dictionary(uniqueKeysWithValues: document.meals.map { ($0.id, $0) })
        document.entries = document.entries.map { sourceEntry in
            var entry = sourceEntry
            let existingClassification = entry.food.meatClassification
            entry.food = enriched(entry.food)
            if entry.isCheatDayAdjustment {
                entry.food.name = "Calorie adjustment"
            }
            entry.mealItems = entry.mealItems?.map { sourceItem in
                var item = sourceItem
                item.food = enriched(item.food)
                return item
            }

            if entry.isMeal, let items = entry.mealItems {
                let totalFiber = items.reduce(.zero) { total, item in
                    total
                        + item.food.nutrients(
                            for: item.amount,
                            unit: item.unit,
                            portionID: item.portionID
                        )
                }.fiber
                entry.nutrients.fiber = totalFiber
                entry.food.nutrients.fiber = totalFiber.map { $0 / max(entry.amount, 0.01) }
            } else if entry.nutrients.fiber == nil {
                entry.nutrients.fiber =
                    entry.food.nutrients(
                        for: entry.amount,
                        unit: entry.unit,
                        portionID: entry.portionID
                    ).fiber
            }

            guard entry.isMeal else { return entry }

            let classification: MeatClassification
            if let mealID = entry.savedMealID, let meal = mealsByID[mealID] {
                classification = MeatClassification(
                    containsProcessedMeat: meal.resolvedContainsProcessedMeat,
                    containsRedMeat: meal.resolvedContainsRedMeat
                )
            } else if let existingClassification {
                classification = existingClassification
            } else {
                classification = meatClassification(for: entry.mealItems ?? [])
            }
            entry.food.containsProcessedMeat = classification.containsProcessedMeat
            entry.food.containsRedMeat = classification.containsRedMeat
            return entry
        }
        return document
    }

    static func fallbackMeatClassification(for name: String) -> MeatClassification {
        func matches(_ pattern: String, in value: String) -> Bool {
            value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        let redPattern =
            #"\b(?:beef|veal|pork|lamb|mutton|goat|venison|deer|elk|moose|bison|buffalo|rabbit|hare|horse|boar)\b"#
        let poultryPattern = #"\b(?:chicken|turkey|duck|goose|poultry)\b"#
        let analogPattern = #"\b(?:meatless|vegetarian|vegan|plant[ -]based|soy)\b"#
        if matches(analogPattern, in: name),
            !matches(redPattern, in: name),
            !matches(poultryPattern, in: name)
        {
            return .none
        }

        var processedName = name.replacingOccurrences(
            of: #"\bleg\s*\(ham\)"#,
            with: "leg",
            options: [.regularExpression, .caseInsensitive]
        )
        processedName = processedName.replacingOccurrences(
            of: #"\bham hocks?\b"#,
            with: "hock",
            options: [.regularExpression, .caseInsensitive]
        )
        processedName = processedName.replacingOccurrences(
            of: #"\b(?:includes? )?cuts? to be cured\b"#,
            with: "cuts",
            options: [.regularExpression, .caseInsensitive]
        )
        let namedProcessedPattern =
            #"\b(?:bacon|ham|hot[ -]?dogs?|frankfurters?|wieners?|luncheon meat|cold cuts?|deli meats?|sausages?|pepperoni|salami|prosciutto|pastrami|pancetta|mortadella|capicola|coppa|soppressata|chorizo|kielbasa|bratwurst|andouille|liverwurst|braunschweiger|corned beef|jerky|biltong|canned meat|spam)\b"#
        let methodPattern = #"\b(?:cured|salted|smoked|fermented|dried|preserved)\b"#
        let animalPattern =
            #"\b(?:beef|veal|pork|lamb|mutton|goat|venison|deer|elk|moose|bison|buffalo|rabbit|hare|horse|boar|chicken|turkey|duck|goose|poultry|meat|offal)\b"#
        let nonMeatNamePattern = #"\b(?:bun|buns|roll|rolls|bread|cracker|crackers|seasoning|flavou?r)\b"#
        var containsProcessed = matches(namedProcessedPattern, in: processedName)
        if containsProcessed,
            matches(nonMeatNamePattern, in: name),
            !matches(redPattern, in: name),
            !matches(poultryPattern, in: name),
            !matches(#"\b(?:sandwich|sub|salad|pizza|soup|burger)\b"#, in: name)
        {
            containsProcessed = false
        }
        containsProcessed =
            containsProcessed || (matches(methodPattern, in: processedName) && matches(animalPattern, in: name))

        let nonMeatRedPattern =
            #"\b(?:beef|pork|lamb)\s+(?:broth|stock|bouillon|flavou?r|extract|gelatin|tallow|fat|suet)\b"#
        let nonMusclePattern =
            #"\b(?:variety meats?|by-products?|brain|heart|kidney|liver|lung|pancreas|spleen|sweetbread|thymus|tongue|tripe|seam fat|fat only)\b"#
        let containsRed =
            matches(redPattern, in: name)
            && !containsProcessed
            && !matches(nonMeatRedPattern, in: name)
            && !matches(nonMusclePattern, in: name)
        return MeatClassification(
            containsProcessedMeat: containsProcessed,
            containsRedMeat: containsRed
        )
    }

    private func resolvedItems(_ items: [MealItem]) -> [MealItem] {
        items.map { item in
            var result = item
            result.food = displayedFood(item.food)
            // Configured nutrition is already an authoritative historical estimate.
            if item.foodConfigurationSnapshot != nil { result.food.nutrients = item.food.nutrients }
            return result
        }
    }

    func logImportedFood(
        _ food: Food,
        saveForReuse: Bool,
        on date: Date,
        allowCheatDay: Bool = false
    ) throws -> Food {
        guard allowCheatDay || canLogFood(on: date) else { throw DiaryDatabaseError.invalidData("Food logging is disabled for this day.") }
        let food = displayedFood(food)
        if saveForReuse { document.customFoods.insert(food, at: 0) }
        log(
            food,
            amount: 1,
            unit: .serving,
            portionID: food.availablePortions.first?.id,
            on: date,
            allowCheatDay: allowCheatDay
        )
        return food
    }

    func logImportedMeal(_ meal: SavedMeal, saveForReuse: Bool = true, amount: Double = 1, on date: Date, allowCheatDay: Bool = false) throws -> SavedMeal {
        guard (allowCheatDay || canLogFood(on: date)), !meal.items.isEmpty, amount.isFinite, amount > 0 else {
            throw DiaryDatabaseError.invalidData("The meal cannot be logged on this day.")
        }
        var resolved = meal
        resolved.items = resolvedItems(meal.items)
        if saveForReuse {
            document.meals.insert(resolved, at: 0)
            logMeal(resolved, amount: amount, on: date, allowCheatDay: allowCheatDay)
        } else {
            logOneOffMeal(resolved, amount: amount, on: date, allowCheatDay: allowCheatDay)
        }
        return resolved
    }

    /// Explicit audit only; normal loading and JSON conversion never reclassify historical records.
    func foodResolutionReview() -> [FoodResolutionReview] {
        let foods = document.customFoods + document.favorites + document.meals.flatMap { $0.items.map(\.food) }
            + document.entries.filter { !$0.isCheatDayAdjustment }.flatMap { entry in
                entry.isMeal ? (entry.mealItems ?? []).map(\.food) : [entry.food]
            }
        var seen = Set<Food>()
        let resolver = FoodResolver(catalog: catalog)
        return foods.compactMap { food in
            guard seen.insert(food).inserted else { return nil }
            let suggestion = resolver.suggestion(for: food)
            let changed = (suggestion.containsProcessedMeat != nil && suggestion.containsProcessedMeat != food.containsProcessedMeat)
                || (suggestion.containsRedMeat != nil && suggestion.containsRedMeat != food.containsRedMeat)
            return changed ? FoodResolutionReview(food: food, suggestion: suggestion) : nil
        }.sorted { $0.food.name.localizedStandardCompare($1.food.name) == .orderedAscending }
    }

    /// Compare snapshots again inside the transaction. Do not overwrite another writer's newer correction.
    func applyFoodResolutionReview(_ review: FoodResolutionReview) throws {
        try applyFoodResolutionReviews([review])
    }

    /// Apply only the reviewed batch, in one pass over original snapshots. A stale item rejects the entire batch.
    func applyFoodResolutionReviews(_ reviews: [FoodResolutionReview]) throws {
        guard !reviews.isEmpty else { return }
        var suggestions: [Food: Food] = [:]
        for review in reviews {
            guard suggestions.updateValue(review.suggestion, forKey: review.food) == nil else {
                throw DiaryDatabaseError.invalidData("A food appears more than once in this review. Reload the suggestions.")
            }
        }
        var matched = Set<Food>()
        func corrected(_ food: Food) -> Food {
            guard let suggestion = suggestions[food] else { return food }
            matched.insert(food)
            return FoodResolver(catalog: catalog).applying(FoodMeatOverrides(
                processed: suggestion.containsProcessedMeat ?? food.containsProcessedMeat,
                red: suggestion.containsRedMeat ?? food.containsRedMeat), to: food)
        }
        func items(_ items: [MealItem]) -> [MealItem] {
            items.map { item in
                var result = item
                result.food = corrected(item.food)
                return result
            }
        }
        var updated = document
        updated.customFoods = document.customFoods.map(corrected)
        updated.favorites = document.favorites.map(corrected)
        updated.meals = document.meals.map { meal in
            var result = meal
            result.items = items(meal.items)
            return result
        }
        for index in document.entries.indices {
            var entry = document.entries[index]
            if entry.isMeal {
                let previousItems = entry.mealItems
                entry.mealItems = entry.mealItems.map(items)
                if entry.mealItems != previousItems {
                    let classification = entryMeatClassification(entry)
                    entry.food.containsProcessedMeat = classification.containsProcessedMeat
                    entry.food.containsRedMeat = classification.containsRedMeat
                }
            } else { entry.food = corrected(entry.food) }
            updated.entries[index] = entry
        }
        guard matched.count == suggestions.count else {
            throw DiaryDatabaseError.invalidData("Some foods changed since review. No classifications were updated. Reload the suggestions.")
        }
        document = updated
    }

    func unknownMeatEntryCount(numberOfDays: Int = 30, referenceDate: Date = Date(),
                               processed: Bool = true, red: Bool = true) -> Int {
        guard numberOfDays > 0 else { return 0 }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate))!
        let start = calendar.date(byAdding: .day, value: -numberOfDays, to: end)!
        return document.entries.filter { entry in
            guard entry.date >= start, entry.date < end, !entry.isCheatDayAdjustment else { return false }
            guard entry.isMeal, let items = entry.mealItems else {
                return (processed && entry.food.containsProcessedMeat == nil) || (red && entry.food.containsRedMeat == nil)
            }
            func unknown(_ key: KeyPath<Food, Bool?>, override: Bool?) -> Bool {
                override == nil && !items.contains { $0.food[keyPath: key] == true }
                    && items.contains { $0.food[keyPath: key] == nil }
            }
            return (processed && unknown(\.containsProcessedMeat, override: entry.processedMeatOverride))
                || (red && unknown(\.containsRedMeat, override: entry.redMeatOverride))
        }.count
    }

    func healthEntries(on date: Date) -> [DiaryEntry] {
        entries(on: date) + (alcoholEntry(on: date).map { [makeAlcoholHealthEntry($0)] } ?? [])
    }

    func suppressesHealthNutrition(on date: Date) -> Bool {
        status(on: date)?.kind == .cheat && calorieAdjustment(on: date) == nil
    }
}
