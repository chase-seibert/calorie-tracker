import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum VitaChaseDeepLink: Equatable {
    case logFood

    static let logFoodURL = URL(string: "vitachase://log-food")!

    init?(url: URL) {
        guard url.scheme?.lowercased() == "vitachase" else { return nil }
        guard url.host?.lowercased() == "log-food" else { return nil }
        self = .logFood
    }
}

enum SharedDiaryStorage {
    static let appGroupIdentifier = "group.com.cseibert.CalorieTracker"
    static let widgetKind = "VitaChaseQuickLog"
    static let caloriesWidgetKind = "VitaChaseCaloriesLeft"
    private static let diagnosticsFileNames = [
        "diary-performance.jsonl",
        "diary-performance.jsonl.1",
        "siri-quick-log.jsonl",
        "siri-quick-log.jsonl.1"
    ]

    static var hasSharedContainer: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
    }

    static var usesSimulatorFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "debug.fixture.active")
            .flatMap(UUID.init(uuidString:)) != nil
        #else
        return false
        #endif
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #if DEBUG && targetEnvironment(simulator)
        if let name = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "debug.fixture.active"),
           UUID(uuidString: name) != nil {
            return root.appendingPathComponent("CalorieTracker/Fixtures/\(name).sqlite")
        }
        #endif
        return root.appendingPathComponent("CalorieTracker", isDirectory: true)
            .appendingPathComponent("Diary.sqlite")
    }

    static func diagnosticsDirectoryURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Library/Diagnostics", isDirectory: true)
    }

    static func migrateLegacyDiagnostics(fileManager: FileManager = .default) {
        let destination = diagnosticsDirectoryURL(fileManager: fileManager)
        let legacy = defaultFileURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("Diagnostics", isDirectory: true)
        guard destination.standardizedFileURL != legacy.standardizedFileURL,
              fileManager.fileExists(atPath: legacy.path) else { return }

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in diagnosticsFileNames {
                let source = legacy.appendingPathComponent(name)
                let target = destination.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path),
                      !fileManager.fileExists(atPath: target.path) else { continue }
                try fileManager.copyItem(at: source, to: target)
            }
        } catch {
            // Diagnostics migration must never interrupt diary actions.
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Rotate to a new isolated database; never unlink a live database or its WAL.
    static func selectFixture(_ variant: String?, reset: Bool = false) -> URL {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        if let variant {
            let key = "debug.fixture.\(variant)"
            let name = reset ? UUID().uuidString : (defaults?.string(forKey: key) ?? UUID().uuidString)
            defaults?.set(name, forKey: key)
            defaults?.set(name, forKey: "debug.fixture.active")
        } else {
            defaults?.removeObject(forKey: "debug.fixture.active")
        }
        return defaultFileURL()
    }
    #endif

    static var legacyDiaryURLs: [URL] {
        var urls: [URL] = []
        if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(root.appendingPathComponent("CalorieTracker/Diary.json"))
        }
        urls.append(legacyFileURL(fileManager: .default))
        return urls
    }

    static var migrationBackupDirectory: URL {
        legacyFileURL(fileManager: .default).deletingLastPathComponent()
            .appendingPathComponent("SQLiteMigrationBackups", isDirectory: true)
    }

    static func reloadWidget() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: caloriesWidgetKind)
#endif
    }

    static func latestQuickLogReceipt() -> QuickLogReceipt? {
        try? DiaryRepository(fileURL: defaultFileURL()).receiptSync()
    }

    private static func legacyFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CalorieTracker", isDirectory: true)
            .appendingPathComponent("Diary.json")
    }


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
    var selectionID: String? = nil
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
            "Yum Chase data isn’t available yet. Open the app once and try again."
        case .unknownItem:
            "That food or meal isn’t in your recent Yum Chase items."
        case .loggingDisabled:
            "Food logging is disabled because today is marked as a cheat day."
        case .saveFailed:
            "Yum Chase couldn’t save that entry."
        case .calorieGoalNotSet:
            "Set a daily calorie goal in Yum Chase first."
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
                    ?? LoggingPreferences.defaultQuantity
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

    init(fileURL: URL = SharedDiaryStorage.defaultFileURL(), calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
    }

    func snapshot(at date: Date = Date()) throws -> QuickLogSnapshot {
        let repository = try DiaryRepository(fileURL: fileURL, calendar: calendar)
        return QuickLogSnapshot(
            document: try repository.snapshotSync(scope: .window(reference: date, selectedDay: date)).document,
            calendar: calendar
        )
    }

    func log(selectionID: String, at date: Date = Date()) throws -> QuickLogResult {
        let repository = try DiaryRepository(fileURL: fileURL, calendar: calendar)
        let result = try repository.performSync(scope: .window(reference: date, selectedDay: date)) { engine in
            guard engine.canLogFood(on: date) else { throw QuickLogError.loggingDisabled }
            guard let result = engine.logQuickSelection(selectionID, on: date) else { throw QuickLogError.unknownItem }
            return result
        }
        SharedDiaryStorage.reloadWidget()
        return result
    }

    func caloriesRemaining(at date: Date = Date()) throws -> Int {
        try snapshot(at: date).caloriesRemaining(at: date)
    }
}

enum LoggingPreferences {
    private static let key = "lastWeightUnit"
    static var lastWeightUnit: LogUnit {
        get {
            let shared = UserDefaults(suiteName: SharedDiaryStorage.appGroupIdentifier)
            let raw = shared?.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
            return LogUnit(rawValue: raw ?? "") ?? .ounces
        }
        set {
            guard newValue == .grams || newValue == .ounces else { return }
            UserDefaults(suiteName: SharedDiaryStorage.appGroupIdentifier)?.set(newValue.rawValue, forKey: key)
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
    static var defaultQuantity: QuantityPreference {
        let unit = lastWeightUnit
        return QuantityPreference(amount: unit == .grams ? 100 : 1, unit: unit)
    }
}
