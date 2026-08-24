import Combine
import Foundation

@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var document: DiaryDocument
    @Published private(set) var lastSaveError: String?

    private let fileURL: URL
    private let calendar: Calendar
    private let healthKit: HealthKitStore?
    private let defaultWeightUnit: LogUnit?

    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        healthKit: HealthKitStore? = nil,
        defaultWeightUnit: LogUnit? = nil,
        referenceDate: Date = Date()
    ) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.healthKit = healthKit
        self.defaultWeightUnit = defaultWeightUnit
        self.document = Self.load(from: self.fileURL) ?? DiaryDocument()
        prepareDayTracking(referenceDate: referenceDate)
    }

    init(
        document: DiaryDocument,
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        healthKit: HealthKitStore? = nil,
        defaultWeightUnit: LogUnit? = nil,
        referenceDate: Date = Date()
    ) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.healthKit = healthKit
        self.defaultWeightUnit = defaultWeightUnit
        self.document = document
        prepareDayTracking(referenceDate: referenceDate)
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

    func foodWeightReport(referenceDate: Date = Date()) -> FoodWeightReport {
        FoodWeightReport(document: document, calendar: calendar, referenceDate: referenceDate)
    }

    func status(on date: Date) -> DayStatus? {
        document.dayStatuses.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func canLogFood(on date: Date) -> Bool {
        status(on: date)?.kind != .cheat
    }

    var dailyCalorieGoal: Int? {
        document.dailyCalorieGoal
    }

    func setDailyCalorieGoal(_ goal: Int?) {
        document.dailyCalorieGoal = goal.flatMap { $0 > 0 ? $0 : nil }
        finalizePastDays(referenceDate: Date())
        persist()
        syncAllHealthData()
    }

    func markCheatDay(on date: Date, adjustmentCalories: Int? = nil) {
        let day = calendar.startOfDay(for: date)
        let normalizedAdjustment = adjustmentCalories.flatMap { $0 > 0 ? $0 : nil }
        let oldAdjustments = entries(on: day).filter(\.isCheatDayAdjustment)
        document.entries.removeAll {
            calendar.isDate($0.date, inSameDayAs: day) && $0.isCheatDayAdjustment
        }

        upsertStatus(DayStatus(
            date: day,
            kind: .cheat,
            source: .manual,
            adjustmentCalories: normalizedAdjustment
        ))

        if let normalizedAdjustment {
            document.entries.append(makeCheatDayAdjustment(
                calories: normalizedAdjustment,
                on: day
            ))
        }

        persist()
        healthKit?.delete(entries: oldAdjustments)
        syncHealthData(on: day)
    }

    func undoCheatDay(on date: Date) {
        guard status(on: date)?.kind == .cheat else { return }
        let day = calendar.startOfDay(for: date)
        let adjustments = entries(on: day).filter(\.isCheatDayAdjustment)
        document.dayStatuses.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        document.entries.removeAll {
            calendar.isDate($0.date, inSameDayAs: day) && $0.isCheatDayAdjustment
        }
        persist()
        healthKit?.delete(entries: adjustments)
        syncHealthData(on: day)
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

    var currentStreak: StreakSummary {
        streak(referenceDate: Date())
    }

    func streak(referenceDate: Date) -> StreakSummary {
        let today = calendar.startOfDay(for: referenceDate)
        var cursor = today

        if status(on: today) == nil && ordinaryEntries(on: today).isEmpty {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return .empty
            }
            cursor = yesterday
        }

        let lowerBound = document.trackingStartDate.map(calendar.startOfDay(for:)) ?? today
        var dates: [Date] = []
        while cursor >= lowerBound {
            guard status(on: cursor) == nil, !ordinaryEntries(on: cursor).isEmpty else { break }
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
            mostPopularItem: mostPopularItem(on: Set(dates))
        )
    }

    func syncAllHealthData() {
        let groupedEntries = Dictionary(grouping: document.entries, by: { calendar.startOfDay(for: $0.date) })
        let statusDays = document.dayStatuses.map { calendar.startOfDay(for: $0.date) }
        for day in Set(groupedEntries.keys).union(statusDays) {
            syncHealthData(on: day)
        }
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
        persist()
    }
#endif

    func log(_ food: Food, amount: Double, unit: LogUnit, portionID: String? = nil, on date: Date) {
        guard canLogFood(on: date) else { return }
        clearAutomaticStatus(on: date)
        let clampedAmount = max(amount, 0.01)
        let foodToLog = displayedFood(food)
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
        persist()
        healthKit?.sync(entries: [entry])
    }

    func delete(entryID: UUID) {
        let deletedEntries = document.entries.filter { $0.id == entryID && !$0.isCheatDayAdjustment }
        guard !deletedEntries.isEmpty else { return }
        document.entries.removeAll { $0.id == entryID && !$0.isCheatDayAdjustment }
        persist()
        healthKit?.delete(entries: deletedEntries)
    }

    func deleteEntries(entryIDs: Set<UUID>) {
        guard !entryIDs.isEmpty else { return }
        let deletedEntries = document.entries.filter {
            entryIDs.contains($0.id) && !$0.isCheatDayAdjustment
        }
        document.entries.removeAll {
            entryIDs.contains($0.id) && !$0.isCheatDayAdjustment
        }
        persist()
        healthKit?.delete(entries: deletedEntries)
    }

    func updateEntry(
        entryID: UUID,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil
    ) {
        guard
            let index = document.entries.firstIndex(where: { $0.id == entryID }),
            !document.entries[index].isMeal,
            !document.entries[index].isCheatDayAdjustment,
            canLogFood(on: document.entries[index].date)
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
        healthKit?.sync(entries: [document.entries[index]])
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
        let rawDefault = defaultWeightUnit?.rawValue ??
            UserDefaults.standard.string(forKey: "defaultWeightUnit") ?? LogUnit.ounces.rawValue
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

    func logMagicSuggestion(_ suggestion: MagicFoodSuggestion, on date: Date) {
        guard canLogFood(on: date) else { return }
        for item in suggestion.items {
            switch item {
            case let .food(food):
                quickLog(food, on: date)
            case let .meal(meal):
                logMeal(meal, on: date)
            }
        }
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
        persist()
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
        persist()
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
        guard lookbackDays > 0, limit > 0 else {
            return MagicFoodSuggestionResult(suggestions: [], hasExcludedMatches: false)
        }
        let timeRange = MagicFoodTimeRange(date: referenceDate, calendar: calendar)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let cutoffDay = calendar.date(
            byAdding: .day,
            value: -lookbackDays,
            to: referenceDay
        ) ?? .distantPast
        let entries = document.entries.filter {
            let entryDay = calendar.startOfDay(for: $0.date)
            return !$0.isCheatDayAdjustment
                && entryDay >= cutoffDay
                && entryDay < referenceDay
                && timeRange.contains($0.loggedAt, calendar: calendar)
        }
        let todayItemIDs = Set(document.entries.compactMap { entry -> String? in
            guard
                !entry.isCheatDayAdjustment,
                calendar.isDate(entry.date, inSameDayAs: referenceDate)
            else { return nil }
            return pickerItem(for: entry)?.id
        })

        struct Observation {
            let item: FoodPickerItem
            let latest: Date
        }
        struct RankedSuggestion {
            let suggestion: MagicFoodSuggestion
            let score: Double
            let latest: Date
        }

        var observationsByDay: [Date: [String: Observation]] = [:]
        var occurrenceCountsByDay: [Date: [String: Int]] = [:]
        for entry in entries {
            guard let item = pickerItem(for: entry) else { continue }
            let day = calendar.startOfDay(for: entry.date)
            occurrenceCountsByDay[day, default: [:]][item.id, default: 0] += 1
            if let current = observationsByDay[day]?[item.id], current.latest >= entry.loggedAt {
                continue
            }
            observationsByDay[day, default: [:]][item.id] = Observation(
                item: item,
                latest: entry.loggedAt
            )
        }

        var itemDays: [String: Set<Date>] = [:]
        var latestObservation: [String: Observation] = [:]
        for (day, observations) in observationsByDay {
            for (itemID, observation) in observations {
                itemDays[itemID, default: []].insert(day)
                if let current = latestObservation[itemID], current.latest >= observation.latest {
                    continue
                }
                latestObservation[itemID] = observation
            }
        }
        let repeatedWithinDayItemIDs = Set(occurrenceCountsByDay.values.flatMap { counts in
            counts.compactMap { itemID, count in count >= 2 ? itemID : nil }
        })

        var hasExcludedMatches = false
        var ranked: [RankedSuggestion] = []
        for (itemID, observation) in latestObservation {
            guard let count = itemDays[itemID]?.count else { continue }
            let isEligible = todayItemIDs.contains(itemID)
                ? repeatedWithinDayItemIDs.contains(itemID)
                : count >= 2
            guard isEligible else {
                if todayItemIDs.contains(itemID) {
                    hasExcludedMatches = true
                }
                continue
            }
            ranked.append(RankedSuggestion(
                suggestion: MagicFoodSuggestion(items: [observation.item]),
                score: Double(count),
                latest: observation.latest
            ))
        }

        var combinationDays: [String: Set<Date>] = [:]
        var combinationItems: [String: [FoodPickerItem]] = [:]
        var combinationLatest: [String: Date] = [:]
        for (day, observations) in observationsByDay {
            let dayItems = observations.values
                .map(\.item)
                .sorted { $0.id < $1.id }
            guard dayItems.count >= 2 else { continue }
            for size in 2...min(3, dayItems.count) {
                for items in combinations(of: dayItems, choosing: size) {
                    let key = items.map(\.id).joined(separator: "|")
                    combinationDays[key, default: []].insert(day)
                    let latest = items
                        .compactMap { observations[$0.id]?.latest }
                        .max() ?? .distantPast
                    if let current = combinationLatest[key], current >= latest {
                        continue
                    }
                    combinationItems[key] = items.sorted {
                        (observations[$0.id]?.latest ?? .distantPast)
                            < (observations[$1.id]?.latest ?? .distantPast)
                    }
                    combinationLatest[key] = latest
                }
            }
        }

        for (key, days) in combinationDays where days.count >= 2 {
            guard let observedItems = combinationItems[key] else { continue }
            let items = observedItems.map { latestObservation[$0.id]?.item ?? $0 }
            let largestItemCount = items.compactMap { itemDays[$0.id]?.count }.max() ?? 0
            guard largestItemCount > 0 else { continue }
            let cohesion = Double(days.count) / Double(largestItemCount)
            guard cohesion >= 0.6 else { continue }
            if items.contains(where: {
                todayItemIDs.contains($0.id) && !repeatedWithinDayItemIDs.contains($0.id)
            }) {
                hasExcludedMatches = true
            }
            ranked.append(RankedSuggestion(
                suggestion: MagicFoodSuggestion(items: items),
                score: Double(days.count) + 1.25 + (Double(items.count - 2) * 0.25),
                latest: combinationLatest[key] ?? .distantPast
            ))
        }

        let eligibleSuggestions = ranked
            .filter { rankedSuggestion in
                rankedSuggestion.suggestion.items.allSatisfy { item in
                    !todayItemIDs.contains(item.id)
                        || repeatedWithinDayItemIDs.contains(item.id)
                }
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.latest != $1.latest { return $0.latest > $1.latest }
                if $0.suggestion.items.count != $1.suggestion.items.count {
                    return $0.suggestion.items.count > $1.suggestion.items.count
                }
                return $0.suggestion.id < $1.suggestion.id
            }
            .map(\.suggestion)

        let suggestions = Array(eligibleSuggestions.prefix(limit))
        return MagicFoodSuggestionResult(
            suggestions: suggestions,
            hasExcludedMatches: suggestions.isEmpty && hasExcludedMatches
        )
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

    @discardableResult
    func updateCustomFood(
        foodID: String,
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        servingGrams: Double
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
            protein: protein
        )
        updatedFood.baseAmountGrams = normalizedServingGrams
        updatedFood.servingGrams = normalizedServingGrams
        updatedFood.servingDescription = "1 serving"
        updatedFood.portions = [FoodPortion(
            id: "custom-serving",
            label: "serving",
            grams: normalizedServingGrams
        )]

        let previousEntries = document.entries
        objectWillChange.send()
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
        let changedEntries = zip(previousEntries, document.entries).compactMap { oldEntry, newEntry in
            oldEntry == newEntry ? nil : newEntry
        }
        persist()
        if !changedEntries.isEmpty {
            healthKit?.sync(entries: changedEntries)
        }
        return true
    }

    @discardableResult
    func saveMeal(name: String, items: [MealItem]) -> SavedMeal? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !items.isEmpty else { return nil }
        let meal = SavedMeal(id: UUID(), name: normalizedName, items: items)
        document.meals.insert(meal, at: 0)
        persist()
        return meal
    }

    @discardableResult
    func updateSavedMeal(mealID: UUID, name: String, items: [MealItem]) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !items.isEmpty,
              let mealIndex = document.meals.firstIndex(where: { $0.id == mealID })
        else { return false }

        let previousEntries = document.entries
        objectWillChange.send()
        document.meals[mealIndex] = SavedMeal(id: mealID, name: normalizedName, items: items)
        for index in document.entries.indices where document.entries[index].savedMealID == mealID {
            var entry = document.entries[index]
            entry.food.name = normalizedName
            refreshMealEntry(&entry)
            document.entries[index] = entry
        }
        let changedEntries = zip(previousEntries, document.entries).compactMap { oldEntry, newEntry in
            oldEntry == newEntry ? nil : newEntry
        }
        persist()
        if !changedEntries.isEmpty {
            healthKit?.sync(entries: changedEntries)
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
        healthKit?.delete(entries: selectedEntries)
        healthKit?.sync(entries: [mealEntry])
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
        healthKit?.delete(entries: [mealEntry])
        healthKit?.sync(entries: expandedEntries)
    }

    func deleteCustomFood(_ food: Food) {
        document.customFoods.removeAll { $0.id == food.id }
        document.favorites.removeAll { $0.id == food.id }
        removeFavoriteOrder(for: "food:\(food.id)")
        document.rememberedQuantities.removeValue(forKey: food.id)
        persist()
    }

    func deleteMeal(_ meal: SavedMeal) {
        document.meals.removeAll { $0.id == meal.id }
        document.favoriteMealIDs.removeAll { $0 == meal.id }
        removeFavoriteOrder(for: "meal:\(meal.id.uuidString)")
        persist()
    }

    func logMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date) {
        guard !meal.items.isEmpty, amount > 0, canLogFood(on: date) else { return }
        clearAutomaticStatus(on: date)
        let entry = makeMealEntry(
            for: meal,
            amount: amount,
            on: date,
            loggedAt: Date(),
            displayOrder: nextDisplayOrder(on: date)
        )
        document.entries.append(entry)
        persist()
        healthKit?.sync(entries: [entry])
    }

    func updateMealEntry(entryID: UUID, amount: Double) {
        guard
            let index = document.entries.firstIndex(where: { $0.id == entryID }),
            document.entries[index].isMeal,
            amount > 0,
            canLogFood(on: document.entries[index].date)
        else { return }

        let entry = document.entries[index]
        let clampedAmount = max(amount, 0.01)
        let baseItems: [MealItem]
        if let savedMealID = entry.savedMealID,
           let savedMeal = document.meals.first(where: { $0.id == savedMealID }) {
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
            total + item.food.nutrients(
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
        persist()
        healthKit?.sync(entries: [document.entries[index]])
    }

    @discardableResult
    func renameMeal(mealID: UUID, name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              document.meals.contains(where: { $0.id == mealID })
        else { return false }

        objectWillChange.send()
        for index in document.meals.indices where document.meals[index].id == mealID {
            document.meals[index].name = normalizedName
        }
        for index in document.entries.indices where document.entries[index].savedMealID == mealID {
            document.entries[index].food.name = normalizedName
        }
        persist()
        return true
    }

    func searchPersonalFoods(_ query: String) -> [Food] {
        let all = personalFoods
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return Array(all.prefix(50)) }
        return all.filter {
            $0.name.localizedStandardContains(normalized) ||
                (document.customFoodNames[$0.id]?.localizedStandardContains(normalized) ?? false) ||
                ($0.brand?.localizedStandardContains(normalized) ?? false)
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
        let fallbackItems = Array(personalResults.prefix(10))
            + catalogFoods
            + Array(personalResults.dropFirst(10))

        var seen = Set<String>()
        return (prioritizedItems + fallbackItems.map { .food(displayedFood($0)) })
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }

    func displayedFood(_ food: Food) -> Food {
        guard let customName = document.customFoodNames[food.id], !customName.isEmpty else {
            return food
        }
        var displayedFood = food
        displayedFood.name = customName
        return displayedFood
    }

    @discardableResult
    func renameFood(foodID: String, name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return false }

        // The rename mutates nested values inside the published document.
        // Announce it explicitly so SwiftUI refreshes the diary immediately.
        objectWillChange.send()
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
        persist()
        return true
    }

    func clearPersonalData() {
        let deletedEntries = document.entries
        let zeroOverrideDays = document.dayStatuses
            .filter { $0.kind == .cheat && $0.adjustmentCalories == nil }
            .map(\.date)
        document = DiaryDocument()
        document.trackingStartDate = calendar.startOfDay(for: Date())
        persist()
        healthKit?.delete(entries: deletedEntries)
        for day in zeroOverrideDays {
            healthKit?.deleteZeroNutrition(on: day)
        }
    }

    func totalsByDay(numberOfDays: Int = 30) -> [(date: Date, nutrients: MacroNutrients)] {
        let today = calendar.startOfDay(for: Date())
        return (0..<numberOfDays).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, totals(on: date))
        }
    }

    private func prepareDayTracking(referenceDate: Date) {
        let today = calendar.startOfDay(for: referenceDate)
        document.schemaVersion = 5
        document.dayStatuses = document.dayStatuses.map { status in
            var normalized = status
            normalized.date = calendar.startOfDay(for: status.date)
            return normalized
        }

        if document.trackingStartDate == nil {
            let firstEntryDay = document.entries.map { calendar.startOfDay(for: $0.date) }.min()
            let firstStatusDay = document.dayStatuses.map { calendar.startOfDay(for: $0.date) }.min()
            document.trackingStartDate = [firstEntryDay, firstStatusDay]
                .compactMap { $0 }
                .min() ?? today
        } else {
            document.trackingStartDate = document.trackingStartDate.map(calendar.startOfDay(for:))
        }

        finalizePastDays(referenceDate: referenceDate)
        persist()
    }

    private func reconcileAutomaticStatus(on date: Date) {
        let day = calendar.startOfDay(for: date)
        if let existing = status(on: day), existing.source == .manual {
            return
        }

        document.dayStatuses.removeAll {
            calendar.isDate($0.date, inSameDayAs: day) && $0.source == .automatic
        }
        let entries = ordinaryEntries(on: day)
        if entries.isEmpty {
            upsertStatus(DayStatus(date: day, kind: .gap, source: .automatic))
            return
        }

        guard let goal = dailyCalorieGoal, goal > 0 else { return }
        let ratio = entries.reduce(.zero) { $0 + $1.nutrients }.calories / Double(goal)
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

    private func ordinaryEntries(on date: Date) -> [DiaryEntry] {
        entries(on: date).filter { !$0.isCheatDayAdjustment }
    }

    private func makeCheatDayAdjustment(calories: Int, on date: Date) -> DiaryEntry {
        let food = Food(
            sourceID: "cheat-day-adjustment",
            source: .custom,
            name: "Cheat day adjustment",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: Double(calories), carbs: 0, fat: 0, protein: 0),
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 adjustment",
            portions: [FoodPortion(id: "cheat-day-adjustment", label: "adjustment", grams: 1)]
        )
        return DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date),
            food: food,
            amount: 1,
            unit: .serving,
            nutrients: food.nutrients,
            loggedAt: Date(),
            portionID: "cheat-day-adjustment",
            displayOrder: nextDisplayOrder(on: date),
            kind: .cheatDayAdjustment
        )
    }

    private func mostPopularItem(on dates: Set<Date>) -> String? {
        let entries = document.entries.filter {
            !$0.isCheatDayAdjustment && dates.contains(calendar.startOfDay(for: $0.date))
        }
        let grouped = Dictionary(grouping: entries, by: { $0.food.name })
        return grouped.max { left, right in
            if left.value.count == right.value.count {
                return left.key.localizedCaseInsensitiveCompare(right.key) == .orderedDescending
            }
            return left.value.count < right.value.count
        }?.key
    }

    private func syncHealthData(on date: Date) {
        guard let healthKit else { return }
        let dayEntries = entries(on: date)
        let dayStatus = status(on: date)
        if dayStatus?.kind == .cheat, dayStatus?.adjustmentCalories == nil {
            healthKit.delete(entries: dayEntries)
            healthKit.syncZeroNutrition(on: calendar.startOfDay(for: date))
        } else {
            healthKit.deleteZeroNutrition(on: calendar.startOfDay(for: date))
            healthKit.sync(entries: dayEntries)
        }
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
        case let .food(food): food.name
        case let .meal(meal): meal.name
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
        food.name.localizedStandardContains(query) ||
            (document.customFoodNames[food.id]?.localizedStandardContains(query) ?? false) ||
            (food.brand?.localizedStandardContains(query) ?? false)
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
        let candidates = document.entries
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
        let firstOrder = document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .compactMap(\.displayOrder)
            .min() ?? 0
        return firstOrder - 1
    }

    private func refreshMealEntry(_ entry: inout DiaryEntry) {
        guard entry.isMeal else { return }
        let baseItems: [MealItem]
        if let savedMealID = entry.savedMealID,
           let savedMeal = document.meals.first(where: { $0.id == savedMealID }) {
            baseItems = savedMeal.items
            entry.food.name = savedMeal.name
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
            total + item.food.nutrients(
                for: item.amount,
                unit: item.unit,
                portionID: item.portionID
            )
        }
        entry.food.nutrients = baseNutrients
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
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)]
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
            mealItems: scaledItems
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
