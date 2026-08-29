import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum SharedDiaryStorage {
    static let appGroupIdentifier = "group.com.cseibert.CalorieTracker"
    static let widgetKind = "VitaChaseQuickLog"
    static let caloriesWidgetKind = "VitaChaseCaloriesLeft"

    private static let lastLoggedSelectionIDKey = "quickLog.lastSelectionID"
    private static let lastLoggedTitleKey = "quickLog.lastTitle"
    private static let lastLoggedDateKey = "quickLog.lastDate"

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        guard let groupRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return legacyFileURL(fileManager: fileManager)
        }

        let sharedURL = groupRoot
            .appendingPathComponent("CalorieTracker", isDirectory: true)
            .appendingPathComponent("Diary.json")
#if !WIDGET_EXTENSION
        migrateLegacyDiaryIfNeeded(to: sharedURL, fileManager: fileManager)
#endif
        return sharedURL
    }

    static func reloadWidget() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: caloriesWidgetKind)
#endif
    }

    static func recordQuickLog(selectionID: String, title: String, at date: Date) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(selectionID, forKey: lastLoggedSelectionIDKey)
        defaults.set(title, forKey: lastLoggedTitleKey)
        defaults.set(date.timeIntervalSince1970, forKey: lastLoggedDateKey)
    }

    static func latestQuickLogReceipt() -> QuickLogReceipt? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let selectionID = defaults.string(forKey: lastLoggedSelectionIDKey),
            let title = defaults.string(forKey: lastLoggedTitleKey)
        else { return nil }
        let timestamp = defaults.double(forKey: lastLoggedDateKey)
        guard timestamp > 0 else { return nil }
        return QuickLogReceipt(
            selectionID: selectionID,
            title: title,
            loggedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private static func legacyFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CalorieTracker", isDirectory: true)
            .appendingPathComponent("Diary.json")
    }

#if !WIDGET_EXTENSION
    private static func migrateLegacyDiaryIfNeeded(to sharedURL: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: sharedURL.path) else { return }
        let legacyURL = legacyFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        do {
            try fileManager.createDirectory(
                at: sharedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacyURL, to: sharedURL)
        } catch {
            // DiaryStore falls back to an empty document only if both the migration
            // and its normal load fail. Keep the legacy copy for recovery.
        }
    }
#endif
}

struct QuickLogReceipt: Equatable, Sendable {
    let selectionID: String
    let title: String
    let loggedAt: Date
}

struct QuickLogSelection: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let itemIDs: [String]
}

struct QuickLogResult: Equatable, Sendable {
    let title: String
    let loggedItemCount: Int
}

enum QuickLogError: LocalizedError, Equatable {
    case unavailable
    case unknownItem
    case loggingDisabled
    case saveFailed
    case calorieGoalNotSet

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "VitaChase data isn’t available yet. Open the app once and try again."
        case .unknownItem:
            "That food or meal isn’t in your recent VitaChase items."
        case .loggingDisabled:
            "Food logging is disabled because today is marked as a cheat day."
        case .saveFailed:
            "VitaChase couldn’t save that entry."
        case .calorieGoalNotSet:
            "Set a daily calorie goal in VitaChase first."
        }
    }
}

struct QuickLogSnapshot: Sendable {
    let document: DiaryDocument
    let calendar: Calendar

    init(document: DiaryDocument, calendar: Calendar = .current) {
        self.document = document
        self.calendar = calendar
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

    func recentSelections(limit: Int = 30) -> [QuickLogSelection] {
        Array(recentItems.prefix(max(limit, 0))).map(selection(for:))
    }

    func recentSelections(matching query: String, limit: Int = 10) -> [QuickLogSelection] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return recentSelections(limit: limit) }

        let recent = recentSelections()
        let queryWithoutArticle = removingLeadingArticle(from: normalizedQuery)
        let matches = recent.filter {
            let title = normalized($0.title)
            return title.contains(normalizedQuery) || title.contains(queryWithoutArticle)
        }
        let exactMatches = matches.filter {
            let title = normalized($0.title)
            return title == normalizedQuery || title == queryWithoutArticle
        }
        if let firstExactMatch = exactMatches.first {
            return [firstExactMatch]
        }

        if let compound = compoundRecentSelection(
            matching: queryWithoutArticle,
            recent: recent
        ) {
            return [compound]
        }
        return Array(matches.prefix(max(limit, 0)))
    }

    func selection(id: String) -> QuickLogSelection? {
        let itemIDs = id.split(separator: "|").map(String.init)
        guard !itemIDs.isEmpty else { return nil }
        let items = itemIDs.compactMap(item(id:))
        guard items.count == itemIDs.count else { return nil }
        return selection(for: items)
    }

    func widgetSelections(at date: Date, limit: Int = 4) -> [QuickLogSelection] {
        let magic = magicSelections(at: date, limit: limit)
        if !magic.isEmpty { return magic }
        return recentSelections(limit: limit)
    }

    func magicSelections(at date: Date, limit: Int = 4) -> [QuickLogSelection] {
        magicSuggestions(at: date, limit: limit).map { selection(for: $0.items) }
    }

    func caloriesRemaining(at date: Date) throws -> Int {
        guard let goal = document.dailyCalorieGoal, goal > 0 else {
            throw QuickLogError.calorieGoalNotSet
        }
        let calories = document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.nutrients.calories }
            + Double(document.alcoholEntries.first {
                calendar.isDate($0.date, inSameDayAs: date)
            }?.calories ?? 0)
        return goal - Int(calories.rounded())
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

    private func selection(for item: FoodPickerItem) -> QuickLogSelection {
        selection(for: [item])
    }

    private func selection(for items: [FoodPickerItem]) -> QuickLogSelection {
        let itemIDs = items.map(\.id).sorted()
        let calories = items.reduce(0) { total, item in
            switch item {
            case let .food(food):
                let preference = document.rememberedQuantities[food.id]
                    ?? QuantityPreference(amount: 1, unit: .ounces)
                return total + food.nutrients(
                    for: preference.amount,
                    unit: preference.unit,
                    portionID: preference.portionID
                ).calories
            case let .meal(meal):
                return total + meal.nutrients.calories
            }
        }
        return QuickLogSelection(
            id: itemIDs.joined(separator: "|"),
            title: items.map(itemName).joined(separator: " + "),
            subtitle: "\(Int(calories.rounded()).formatted()) cal",
            itemIDs: itemIDs
        )
    }

    func item(id: String) -> FoodPickerItem? {
        if id.hasPrefix("meal:"),
           let mealID = UUID(uuidString: String(id.dropFirst("meal:".count))),
           let meal = document.meals.first(where: { $0.id == mealID }) {
            return .meal(meal)
        }
        guard id.hasPrefix("food:") else { return nil }
        let foodID = String(id.dropFirst("food:".count))
        let candidates = document.entries
            .filter { !$0.isMeal && !$0.isCheatDayAdjustment }
            .sorted { $0.loggedAt > $1.loggedAt }
            .map(\.food) + document.favorites + document.customFoods
        guard let food = candidates.first(where: { $0.id == foodID }) else { return nil }
        return .food(displayedFood(food))
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

    private func displayedFood(_ food: Food) -> Food {
        guard let customName = document.customFoodNames[food.id] else { return food }
        var renamed = food
        renamed.name = customName
        return renamed
    }

    private func itemName(_ item: FoodPickerItem) -> String {
        switch item {
        case let .food(food): food.name
        case let .meal(meal): meal.name
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compoundRecentSelection(
        matching query: String,
        recent: [QuickLogSelection]
    ) -> QuickLogSelection? {
        let separated = query
            .replacingOccurrences(of: ",", with: " and ")
            .replacingOccurrences(of: " & ", with: " and ")
        let requestedNames = separated.components(separatedBy: " and ")
            .map(removingLeadingArticle)
            .filter { !$0.isEmpty }
        guard requestedNames.count > 1 else { return nil }

        var matchedSelections: [QuickLogSelection] = []
        for requestedName in requestedNames {
            guard let match = recent.first(where: {
                normalized($0.title) == requestedName
            }) else { return nil }
            matchedSelections.append(match)
        }

        let items = matchedSelections
            .flatMap(\.itemIDs)
            .compactMap(item(id:))
        guard items.count == matchedSelections.flatMap(\.itemIDs).count else { return nil }
        return selection(for: items)
    }

    private func removingLeadingArticle(from value: String) -> String {
        for prefix in ["a ", "an ", "the ", "some "] where value.hasPrefix(prefix) {
            return String(value.dropFirst(prefix.count))
        }
        return value
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
}

struct QuickLogRepository: Sendable {
    let fileURL: URL
    let calendar: Calendar

    init(
        fileURL: URL = SharedDiaryStorage.defaultFileURL(),
        calendar: Calendar = .current
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
    }

    func snapshot() throws -> QuickLogSnapshot {
        QuickLogSnapshot(document: try load(), calendar: calendar)
    }

    func log(selectionID: String, at date: Date = Date()) throws -> QuickLogResult {
        var document = try load()
        let snapshot = QuickLogSnapshot(document: document, calendar: calendar)
        guard let selection = snapshot.selection(id: selectionID) else {
            throw QuickLogError.unknownItem
        }
        let day = calendar.startOfDay(for: date)
        if document.dayStatuses.contains(where: {
            calendar.isDate($0.date, inSameDayAs: day) && $0.kind == .cheat
        }) {
            throw QuickLogError.loggingDisabled
        }

        document.dayStatuses.removeAll {
            calendar.isDate($0.date, inSameDayAs: day) && $0.source == .automatic
        }
        if document.trackingStartDate == nil {
            document.trackingStartDate = day
        }

        var loggedCount = 0
        for itemID in selection.itemIDs {
            let currentSnapshot = QuickLogSnapshot(document: document, calendar: calendar)
            guard let item = currentSnapshot.item(id: itemID) else { continue }
            if itemID.hasPrefix("meal:"),
               let mealID = UUID(uuidString: String(itemID.dropFirst("meal:".count))),
               let meal = document.meals.first(where: { $0.id == mealID }) {
                document.entries.append(makeMealEntry(meal, on: day, document: document, loggedAt: date))
                loggedCount += 1
                continue
            }

            guard itemID.hasPrefix("food:") else { continue }
            let foodID = String(itemID.dropFirst("food:".count))
            guard case let .food(food) = item else { continue }
            let preference = document.rememberedQuantities[foodID]
                ?? QuantityPreference(amount: 1, unit: .ounces)
            let amount = max(preference.amount, 0.01)
            document.entries.append(DiaryEntry(
                id: UUID(),
                date: day,
                food: food,
                amount: amount,
                unit: preference.unit,
                nutrients: food.nutrients(
                    for: amount,
                    unit: preference.unit,
                    portionID: preference.portionID
                ),
                loggedAt: date,
                portionID: preference.portionID,
                displayOrder: nextDisplayOrder(on: day, document: document)
            ))
            document.rememberedQuantities[foodID] = preference
            loggedCount += 1
        }

        guard loggedCount == selection.itemIDs.count else { throw QuickLogError.unknownItem }
        try save(document)
        SharedDiaryStorage.recordQuickLog(
            selectionID: selection.id,
            title: selection.title,
            at: date
        )
        SharedDiaryStorage.reloadWidget()
        return QuickLogResult(title: selection.title, loggedItemCount: loggedCount)
    }

    func caloriesRemaining(at date: Date = Date()) throws -> Int {
        try snapshot().caloriesRemaining(at: date)
    }

    private func load() throws -> DiaryDocument {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw QuickLogError.unavailable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(DiaryDocument.self, from: data) else {
            throw QuickLogError.unavailable
        }
        return document
    }

    private func save(_ document: DiaryDocument) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(document).write(to: fileURL, options: .atomic)
        } catch {
            throw QuickLogError.saveFailed
        }
    }

    private func nextDisplayOrder(on date: Date, document: DiaryDocument) -> Int {
        let firstOrder = document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .compactMap(\.displayOrder)
            .min() ?? 0
        return firstOrder - 1
    }

    private func makeMealEntry(
        _ meal: SavedMeal,
        on date: Date,
        document: DiaryDocument,
        loggedAt: Date
    ) -> DiaryEntry {
        let mealFood = Food(
            sourceID: "saved-meal-\(meal.id.uuidString)",
            source: .custom,
            name: meal.name,
            brand: nil,
            barcode: nil,
            nutrients: meal.nutrients,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 meal",
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)],
            containsProcessedMeat: meal.resolvedContainsProcessedMeat,
            containsRedMeat: meal.resolvedContainsRedMeat
        )
        return DiaryEntry(
            id: UUID(),
            date: date,
            food: mealFood,
            amount: 1,
            unit: .serving,
            nutrients: meal.nutrients,
            loggedAt: loggedAt,
            portionID: "saved-meal",
            displayOrder: nextDisplayOrder(on: date, document: document),
            savedMealID: meal.id,
            mealItems: meal.items
        )
    }
}
