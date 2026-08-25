import Combine
import XCTest
@testable import CalorieTracker

final class CalorieTrackerTests: XCTestCase {
    func testAnalyticsDiagnosticEventDecodesHistoryWithoutPayload() throws {
        let data = Data(#"{"id":"event-001","type":"app.launched","occurredAt":"2026-08-25T12:00:00Z","state":"uploaded"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(AnalyticsDiagnosticEvent.self, from: data)

        XCTAssertEqual(event.id, "event-001")
        XCTAssertNil(event.payload)
    }

    func testAnalyticsDiagnosticPayloadFormatsCanonicalEventJSON() {
        let payload = AnalyticsDiagnosticPayload(
            eventId: "event-001",
            type: "food_search.no_match",
            occurredAt: Date(timeIntervalSince1970: 0),
            audience: .debug,
            sessionId: "session-001",
            properties: ["query": "dragon fruit"]
        )

        XCTAssertTrue(payload.formattedJSON.contains(#""eventId" : "event-001""#))
        XCTAssertTrue(payload.formattedJSON.contains(#""audience" : "debug""#))
        XCTAssertTrue(payload.formattedJSON.contains(#""query" : "dragon fruit""#))
    }

    func testFoodLogAnalyticsIdentifiesCatalogFoodWithoutSendingDisplayText() {
        let food = Food(
            sourceID: "171705",
            source: .usda,
            name: "Banana, raw",
            brand: "Example brand",
            barcode: nil,
            nutrients: MacroNutrients(calories: 89, carbs: 23, fat: 0.3, protein: 1.1),
            baseAmountGrams: 100,
            servingGrams: 118,
            servingDescription: "1 medium"
        )

        let properties = FoodLogAnalytics.foodProperties(
            food: food,
            method: "quick_add",
            mode: "search",
            unit: .ounces,
            isFavorite: true,
            catalogVersion: "abc123def456",
            selectionRank: 2,
            query: "  banana  "
        )

        XCTAssertEqual(properties["source"], "usda")
        XCTAssertEqual(properties["source_id"], "171705")
        XCTAssertEqual(properties["catalog_version"], "abc123def456")
        XCTAssertEqual(properties["food_kind"], "catalog")
        XCTAssertEqual(properties["is_favorite"], "true")
        XCTAssertEqual(properties["selection_rank"], "2")
        XCTAssertEqual(properties["query"], "banana")
        XCTAssertEqual(properties["has_brand"], "true")
        XCTAssertEqual(properties["has_barcode"], "false")
        XCTAssertEqual(properties["has_portions"], "true")
        XCTAssertNil(properties["local_item_id"])
        XCTAssertNil(properties["name"])
        XCTAssertNil(properties["brand"])
        XCTAssertNil(properties["barcode"])
    }

    func testFoodLogAnalyticsUsesLocalIdentityForCustomFood() {
        let food = Food(
            sourceID: "local-food-001",
            source: .custom,
            name: "Private custom name",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )

        let properties = FoodLogAnalytics.foodProperties(
            food: food,
            method: "quantity_editor",
            mode: "favorites",
            unit: .grams,
            isFavorite: false,
            catalogVersion: "ignored-for-custom"
        )

        XCTAssertEqual(properties["local_item_id"], "local-food-001")
        XCTAssertEqual(properties["food_kind"], "custom")
        XCTAssertNil(properties["source_id"])
        XCTAssertNil(properties["catalog_version"])
        XCTAssertNil(properties["query"])
    }

    func testAnalyticsGzipIsDeterministicAndValidForStoredBlock() {
        let encoded = GzipEncoder.encode(Data("hello".utf8))

        XCTAssertEqual(Array(encoded.prefix(10)), [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        XCTAssertEqual(Array(encoded[10..<15]), [0x01, 0x05, 0x00, 0xfa, 0xff])
        XCTAssertEqual(String(data: encoded[15..<20], encoding: .utf8), "hello")
        XCTAssertEqual(Array(encoded.suffix(8)), [0x86, 0xa6, 0x10, 0x36, 0x05, 0x00, 0x00, 0x00])
        XCTAssertEqual(encoded, GzipEncoder.encode(Data("hello".utf8)))
    }

    func testAnalyticsRequestSigningUsesSpecifiedCanonicalText() {
        let payloadSHA = AnalyticsRequestSigner.payloadSHA256(Data("abc".utf8))
        let signature = AnalyticsRequestSigner.signature(
            namespace: "calorie-tracker",
            apiVersion: "v1",
            batchID: "batch-001",
            payloadSHA256: payloadSHA,
            secret: "test-secret"
        )

        XCTAssertEqual(payloadSHA, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(signature, "4b83cfa537f94dc2f283f784a53528c04ca44d72a6b4cb13f54b13f2ee882376")
    }

    func testFoodSearchAttemptRecordsTerminalOutcomesOnce() {
        var noMatch = FoodSearchAttemptTracker()
        noMatch.completed(query: " dragon fruit ", resultCount: 0)
        XCTAssertEqual(
            noMatch.finish(query: "dragon fruit", isSearching: false),
            FoodSearchOutcome(eventType: "food_search.no_match", query: "dragon fruit", resultCount: 0)
        )
        XCTAssertNil(noMatch.finish(query: "dragon fruit", isSearching: false))

        var abandoned = FoodSearchAttemptTracker()
        abandoned.completed(query: "banana", resultCount: 4)
        XCTAssertEqual(
            abandoned.finish(query: "banana", isSearching: false),
            FoodSearchOutcome(eventType: "food_search.nothing_selected", query: "banana", resultCount: 4)
        )

        var logged = FoodSearchAttemptTracker()
        logged.completed(query: "banana", resultCount: 4)
        logged.logged(query: "banana")
        XCTAssertNil(logged.finish(query: "banana", isSearching: false))
    }

    func testFoodPickerLaunchPreservesRequestedMode() {
        let launch = FoodPickerLaunch.mode(.meals)

        XCTAssertEqual(launch.initialMode?.rawValue, FoodPickerView.Mode.meals.rawValue)
        XCTAssertNil(FoodPickerLaunch.search.initialMode)
    }

    @MainActor
    func testMagicSuggestionsPromoteReliableMorningSetAndLunchSingleton() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour,
                minute: 30
            ))!
        }
        func food(_ id: String, _ name: String) -> Food {
            Food(
                sourceID: id,
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
                baseAmountGrams: 100,
                servingGrams: 100,
                servingDescription: "1 serving"
            )
        }
        func entry(_ food: Food, day: Int, hour: Int) -> DiaryEntry {
            DiaryEntry(
                id: UUID(),
                date: calendar.startOfDay(for: date(day, hour)),
                food: food,
                amount: 1,
                unit: .serving,
                nutrients: food.nutrients,
                loggedAt: date(day, hour)
            )
        }

        let cappuccino = food("cappuccino", "Cappuccino")
        let proteinShake = food("protein-shake", "Protein shake")
        let turkeySandwich = food("turkey-sandwich", "Turkey sandwich")
        let tea = food("tea", "Tea with honey")
        let oneOffBreakfast = food("one-off-breakfast", "One-off breakfast")
        let oldBreakfast = food("old-breakfast", "Old breakfast")
        var oldBreakfastEntry = entry(oldBreakfast, day: 7, hour: 7)
        oldBreakfastEntry.date = calendar.date(byAdding: .day, value: -20, to: oldBreakfastEntry.date)!
        oldBreakfastEntry.loggedAt = calendar.date(byAdding: .day, value: -20, to: oldBreakfastEntry.loggedAt)!
        var document = DiaryDocument()
        document.entries = [
            entry(cappuccino, day: 5, hour: 6),
            entry(proteinShake, day: 5, hour: 6),
            entry(cappuccino, day: 6, hour: 7),
            entry(proteinShake, day: 6, hour: 7),
            entry(cappuccino, day: 7, hour: 8),
            entry(oneOffBreakfast, day: 7, hour: 9),
            entry(turkeySandwich, day: 4, hour: 12),
            entry(turkeySandwich, day: 5, hour: 12),
            entry(tea, day: 5, hour: 12),
            entry(turkeySandwich, day: 6, hour: 13),
            entry(tea, day: 6, hour: 13),
            entry(turkeySandwich, day: 7, hour: 12),
            oldBreakfastEntry
        ]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(
            document: document,
            fileURL: folder.appendingPathComponent("diary.json"),
            calendar: calendar,
            referenceDate: date(8, 10)
        )

        let breakfast = store.magicSuggestions(at: date(8, 10))
        XCTAssertEqual(breakfast.first?.items.map(\.id).sorted(), [
            "food:\(cappuccino.id)",
            "food:\(proteinShake.id)"
        ])
        XCTAssertTrue(breakfast.contains { $0.items.map(\.id) == ["food:\(cappuccino.id)"] })
        XCTAssertFalse(breakfast.contains { $0.items.map(\.id) == ["food:\(oneOffBreakfast.id)"] })
        XCTAssertFalse(breakfast.contains { $0.items.contains { $0.id == "food:\(oldBreakfast.id)" } })

        let lunch = store.magicSuggestions(at: date(8, 12))
        XCTAssertEqual(lunch.first?.items.map(\.id), ["food:\(turkeySandwich.id)"])
    }

    @MainActor
    func testLoggingMagicSetCreatesSeparateDiaryEntries() {
        func food(_ id: String, _ name: String) -> Food {
            Food(
                sourceID: id,
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
                baseAmountGrams: 100,
                servingGrams: 100,
                servingDescription: "1 serving"
            )
        }
        let cappuccino = food("magic-cappuccino", "Cappuccino")
        let proteinShake = food("magic-protein-shake", "Protein shake")
        let suggestion = MagicFoodSuggestion(items: [.food(cappuccino), .food(proteinShake)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))

        let loggedItems = store.logMagicSuggestion(suggestion, on: Date())

        XCTAssertEqual(loggedItems, suggestion.items)
        XCTAssertEqual(Set(store.entries(on: Date()).map(\.food.name)), ["Cappuccino", "Protein shake"])
        XCTAssertTrue(store.entries(on: Date()).allSatisfy { !$0.isMeal })
        XCTAssertTrue(store.document.meals.isEmpty)
    }

    @MainActor
    func testMagicSuggestionsRequireSameDayHistoricalRepeatForItemsLoggedToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour,
                minute: 30
            ))!
        }
        func food(_ id: String, _ name: String) -> Food {
            Food(
                sourceID: id,
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
                baseAmountGrams: 100,
                servingGrams: 100,
                servingDescription: "1 serving"
            )
        }
        func entry(_ food: Food, day: Int, hour: Int) -> DiaryEntry {
            DiaryEntry(
                id: UUID(),
                date: calendar.startOfDay(for: date(day, hour)),
                food: food,
                amount: 1,
                unit: .serving,
                nutrients: food.nutrients,
                loggedAt: date(day, hour)
            )
        }

        let cappuccino = food("cappuccino", "Cappuccino")
        let proteinShake = food("protein-shake", "Protein shake")
        let oneOff = food("one-off", "One-off lunch")
        let history = [
            entry(cappuccino, day: 5, hour: 12),
            entry(cappuccino, day: 5, hour: 12),
            entry(proteinShake, day: 5, hour: 12),
            entry(proteinShake, day: 5, hour: 12),
            entry(oneOff, day: 5, hour: 12),
            entry(cappuccino, day: 6, hour: 12),
            entry(proteinShake, day: 6, hour: 12),
            entry(oneOff, day: 6, hour: 12)
        ]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var unloggedDocument = DiaryDocument()
        unloggedDocument.entries = history
        let unloggedStore = DiaryStore(
            document: unloggedDocument,
            fileURL: folder.appendingPathComponent("unlogged-diary.json"),
            calendar: calendar,
            referenceDate: date(8, 12)
        )

        XCTAssertTrue(unloggedStore.magicSuggestions(at: date(8, 12)).contains {
            Set($0.items.map(\.id)) == ["food:\(cappuccino.id)", "food:\(proteinShake.id)"]
        })

        var loggedDocument = DiaryDocument()
        loggedDocument.entries = history + [
            entry(cappuccino, day: 8, hour: 8),
            entry(oneOff, day: 8, hour: 8)
        ]
        let loggedStore = DiaryStore(
            document: loggedDocument,
            fileURL: folder.appendingPathComponent("logged-diary.json"),
            calendar: calendar,
            referenceDate: date(8, 12)
        )
        let suggestions = loggedStore.magicSuggestions(at: date(8, 12), limit: 10)

        XCTAssertTrue(suggestions.contains { suggestion in
            Set(suggestion.items.map(\.id)) == [
                "food:\(cappuccino.id)",
                "food:\(proteinShake.id)"
            ]
        })
        XCTAssertTrue(suggestions.contains {
            $0.items.map(\.id) == ["food:\(cappuccino.id)"]
        })
        XCTAssertTrue(suggestions.contains {
            $0.items.map(\.id) == ["food:\(proteinShake.id)"]
        })
        XCTAssertFalse(suggestions.contains { suggestion in
            suggestion.items.contains { $0.id == "food:\(oneOff.id)" }
        })
    }

    @MainActor
    func testMagicSuggestionResultDistinguishesExcludedMatchesFromNoPattern() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour,
                minute: 30
            ))!
        }
        let food = Food(
            sourceID: "excluded-magic-food",
            source: .custom,
            name: "Usual breakfast",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
            baseAmountGrams: 100,
            servingGrams: 100,
            servingDescription: "1 serving"
        )
        func entry(on day: Int) -> DiaryEntry {
            DiaryEntry(
                id: UUID(),
                date: calendar.startOfDay(for: date(day, 8)),
                food: food,
                amount: 1,
                unit: .serving,
                nutrients: food.nutrients,
                loggedAt: date(day, 8)
            )
        }

        var document = DiaryDocument()
        document.entries = [entry(on: 5), entry(on: 6), entry(on: 8)]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(
            document: document,
            fileURL: folder.appendingPathComponent("diary.json"),
            calendar: calendar,
            referenceDate: date(8, 8)
        )

        let excludedResult = store.magicSuggestionResult(at: date(8, 8))
        XCTAssertTrue(excludedResult.suggestions.isEmpty)
        XCTAssertTrue(excludedResult.hasExcludedMatches)

        let emptyStore = DiaryStore(
            document: DiaryDocument(),
            fileURL: folder.appendingPathComponent("empty-diary.json"),
            calendar: calendar,
            referenceDate: date(8, 8)
        )
        let noPatternResult = emptyStore.magicSuggestionResult(at: date(8, 8))
        XCTAssertTrue(noPatternResult.suggestions.isEmpty)
        XCTAssertFalse(noPatternResult.hasExcludedMatches)
    }

    @MainActor
    func testSimulatorFixtureRebasesAndSeedsEveryMagicTimeRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour
            ))!
        }
        func food(_ index: Int, _ name: String) -> Food {
            Food(
                sourceID: "fixture-\(index)",
                source: .custom,
                name: name,
                brand: "Fixture",
                barcode: nil,
                nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
                baseAmountGrams: 1,
                servingGrams: 1,
                servingDescription: "1 item"
            )
        }

        let names = [
            "Cappuccino",
            "Protein shake",
            "Turkey sandwich",
            "Tea with honey",
            "Chili, no rice",
            "Rice, white, cooked, glutinous",
            "Fixture snack"
        ]
        let capturedReferenceDate = date(5, 0)
        var source = DiaryDocument()
        source.entries = names.enumerated().map { index, name in
            let food = food(index, name)
            return DiaryEntry(
                id: UUID(),
                date: capturedReferenceDate,
                food: food,
                amount: 1,
                unit: .serving,
                nutrients: food.nutrients,
                loggedAt: date(5, 6 + index)
            )
        }
        let destinationDate = date(20, 5)
        let document = DiaryFixtureLoader.rebasedDocument(
            source,
            from: capturedReferenceDate,
            to: destinationDate,
            calendar: calendar
        )
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(
            document: document,
            fileURL: folder.appendingPathComponent("diary.json"),
            calendar: calendar,
            referenceDate: destinationDate
        )

        for offset in -1...1 {
            let day = calendar.date(byAdding: .day, value: offset, to: destinationDate)!
            XCTAssertFalse(store.entries(on: day).isEmpty)
        }

        let expectations: [(hour: Int, names: Set<String>)] = [
            (5, ["Cappuccino", "Protein shake"]),
            (11, ["Turkey sandwich", "Tea with honey"]),
            (15, ["Chili, no rice", "Rice, white, cooked, glutinous"])
        ]
        for expectation in expectations {
            let suggestion = try XCTUnwrap(
                store.magicSuggestions(at: date(20, expectation.hour)).first
            )
            let suggestedNames = Set(suggestion.items.map {
                switch $0 {
                case let .food(food): food.name
                case let .meal(meal): meal.name
                }
            })
            XCTAssertEqual(suggestedNames, expectation.names)
        }
    }

    @MainActor
    func testDailyCalorieGoalPersistsAndCanBeRemoved() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let store = DiaryStore(fileURL: fileURL)

        XCTAssertNil(store.dailyCalorieGoal)
        store.setDailyCalorieGoal(2_200)
        XCTAssertEqual(store.dailyCalorieGoal, 2_200)
        XCTAssertEqual(DiaryStore(fileURL: fileURL).dailyCalorieGoal, 2_200)

        store.setDailyCalorieGoal(0)
        XCTAssertNil(store.dailyCalorieGoal)
        XCTAssertNil(DiaryStore(fileURL: fileURL).dailyCalorieGoal)
    }

    func testDailyCalorieProgressIncludesOptionalGoal() {
        let progress = DailyCalorieProgress(calories: 1_234.5, goal: 2_000)
        XCTAssertEqual(progress.consumed, 1_235)
        XCTAssertEqual(progress.goal, 2_000)
        XCTAssertEqual(progress.remaining, 765)
        XCTAssertEqual(progress.fraction ?? -1, 0.6175, accuracy: 0.0001)
        let overGoal = DailyCalorieProgress(calories: 2_100, goal: 2_000)
        XCTAssertEqual(overGoal.remaining, 0)
        XCTAssertEqual(overGoal.over, 100)
        XCTAssertEqual(overGoal.fraction, 1)
        XCTAssertEqual(
            DailyCalorieProgress(calories: 1_234.4, goal: nil).accessibilityLabel,
            "1234 calories"
        )
        XCTAssertEqual(
            DailyCalorieProgress(calories: 1_234.4, goal: 2_000).accessibilityLabel,
            "1234 calories, 766 left"
        )
        XCTAssertEqual(overGoal.accessibilityLabel, "2100 calories, 100 over")
    }

    @MainActor
    func testLoggingScalesNutrientsAndRemembersQuantity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let food = Food(
            sourceID: "banana",
            source: .usda,
            name: "Banana",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 89, carbs: 22.8, fat: 0.3, protein: 1.1),
            baseAmountGrams: 100,
            servingGrams: 118,
            servingDescription: "1 medium"
        )

        store.log(food, amount: 50, unit: .grams, on: Date())

        let entry = try XCTUnwrap(store.entries(on: Date()).first)
        XCTAssertEqual(entry.nutrients.calories, 44.5, accuracy: 0.001)
        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 50, unit: .grams))
    }

    @MainActor
    func testDeletingMultipleEntriesRemovesOnlySelectedItemsAndPersists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        func food(_ name: String, calories: Double) -> Food {
            Food(
                sourceID: name.lowercased(),
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: calories, carbs: 1, fat: 1, protein: 1),
                baseAmountGrams: 100,
                servingGrams: nil,
                servingDescription: nil
            )
        }

        store.log(food("Toast", calories: 100), amount: 100, unit: .grams, on: day)
        store.log(food("Eggs", calories: 200), amount: 100, unit: .grams, on: day)
        store.log(food("Coffee", calories: 5), amount: 100, unit: .grams, on: day)
        let selectedIDs = Set(
            store.entries(on: day)
                .filter { $0.food.name != "Eggs" }
                .map(\.id)
        )

        store.deleteEntries(entryIDs: selectedIDs)

        XCTAssertEqual(store.entries(on: day).map(\.food.name), ["Eggs"])
        XCTAssertEqual(store.totals(on: day).calories, 200)
        XCTAssertEqual(DiaryStore(fileURL: fileURL).entries(on: day).map(\.food.name), ["Eggs"])
    }

    @MainActor
    func testEditingLoggedFoodUpdatesEntryTotalsPreferenceAndPersistence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let egg = Food(
            sourceID: "scrambled-egg-edit",
            source: .usda,
            name: "Egg, whole, cooked, scrambled",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 150, carbs: 2, fat: 10, protein: 10),
            baseAmountGrams: 100,
            servingGrams: 50,
            servingDescription: "1 egg",
            portions: [FoodPortion(id: "one-egg", label: "egg", grams: 50)]
        )
        let store = DiaryStore(fileURL: fileURL)
        store.log(egg, amount: 100, unit: .grams, on: day)
        let originalEntry = try XCTUnwrap(store.entries(on: day).first)

        store.updateEntry(
            entryID: originalEntry.id,
            amount: 2,
            unit: .serving,
            portionID: "one-egg"
        )

        let editedEntry = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertEqual(store.entries(on: day).count, 1)
        XCTAssertEqual(editedEntry.id, originalEntry.id)
        XCTAssertEqual(editedEntry.amount, 2)
        XCTAssertEqual(editedEntry.unit, .serving)
        XCTAssertEqual(editedEntry.portionID, "one-egg")
        XCTAssertEqual(editedEntry.nutrients.calories, 150, accuracy: 0.001)
        XCTAssertEqual(store.totals(on: day).calories, 150, accuracy: 0.001)
        XCTAssertEqual(store.preference(for: egg), QuantityPreference(amount: 2, unit: .serving, portionID: "one-egg"))

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).first?.amount, 2)
        XCTAssertEqual(reloaded.entries(on: day).first?.unit, .serving)
        XCTAssertEqual(reloaded.totals(on: day).calories, 150, accuracy: 0.001)
    }

    @MainActor
    func testRenamingLoggedFoodUpdatesEveryPersonalCopyAndSearchesByCustomName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let food = Food(
            sourceID: "rename-me",
            source: .usda,
            name: "Chicken breast, roasted",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 165, carbs: 0, fat: 3.6, protein: 31),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        let store = DiaryStore(fileURL: fileURL)

        store.log(food, amount: 100, unit: .grams, on: day)
        store.toggleFavorite(food)

        XCTAssertTrue(store.renameFood(foodID: food.id, name: "My chicken"))
        XCTAssertEqual(store.entries(on: day).first?.food.name, "My chicken")
        XCTAssertEqual(store.document.favorites.first?.name, "My chicken")
        XCTAssertEqual(store.displayedFood(food).name, "My chicken")
        XCTAssertEqual(store.searchPersonalFoods("my chicken").first?.name, "My chicken")

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).first?.food.name, "My chicken")
        XCTAssertEqual(reloaded.searchPersonalFoods("chicken").first?.name, "My chicken")
    }

    @MainActor
    func testRenamingLoggedFoodPublishesAnImmediateChange() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let food = Food(
            sourceID: "rename-publish",
            source: .custom,
            name: "Original name",
            brand: nil,
            barcode: nil,
            nutrients: .zero,
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        store.log(food, amount: 100, unit: .grams, on: Date())

        var changeCount = 0
        let cancellation = store.objectWillChange.sink { _ in changeCount += 1 }
        defer { cancellation.cancel() }

        XCTAssertTrue(store.renameFood(foodID: food.id, name: "New name"))
        XCTAssertGreaterThan(changeCount, 0)
    }

    @MainActor
    func testFavoritePersistsSelectedNaturalPortionWithoutLogging() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let egg = Food(
            sourceID: "scrambled-egg",
            source: .usda,
            name: "Egg, whole, cooked, scrambled",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 149, carbs: 1.6, fat: 10, protein: 10),
            baseAmountGrams: 100,
            servingGrams: 61,
            servingDescription: "1 large egg",
            portions: [FoodPortion(id: "large-egg", label: "large egg", grams: 61)]
        )
        let preference = QuantityPreference(amount: 1, unit: .serving, portionID: "large-egg")
        let store = DiaryStore(fileURL: fileURL)

        store.toggleFavorite(egg, preference: preference)

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.isFavorite(egg))
        XCTAssertEqual(reloaded.preference(for: egg), preference)
    }

    @MainActor
    func testFavoriteMealPersistsAndIsRemovedWhenMealIsDeleted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let food = Food(
            sourceID: "favorite-meal-food",
            source: .custom,
            name: "Toast",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 20, fat: 1, protein: 3),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        let store = DiaryStore(fileURL: fileURL)

        store.saveMeal(
            name: "Zebra meal",
            items: [MealItem(id: UUID(), food: food, amount: 100, unit: .grams)]
        )
        let meal = try XCTUnwrap(store.document.meals.first)
        store.toggleFavorite(food)
        store.toggleFavorite(meal)

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.isFavorite(meal))
        XCTAssertEqual(reloaded.favoriteMeals.map(\.id), [meal.id])
        XCTAssertEqual(
            reloaded.favoriteItems.map(\.id),
            ["food:\(food.id)", "meal:\(meal.id.uuidString)"]
        )

        reloaded.deleteMeal(meal)
        XCTAssertTrue(reloaded.favoriteMeals.isEmpty)
        XCTAssertFalse(reloaded.document.favoriteMealIDs.contains(meal.id))
        XCTAssertEqual(reloaded.favoriteItems.map(\.id), ["food:\(food.id)"])
    }

    @MainActor
    func testSearchPromotesAlphabetizedFavoriteFoodsAndSavedMeals() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))

        func food(_ id: String, _ name: String) -> Food {
            Food(
                sourceID: id,
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5),
                baseAmountGrams: 100,
                servingGrams: 100,
                servingDescription: "1 serving"
            )
        }

        let favorite = food("favorite-zebra", "Zebra favorite")
        let logged = food("logged-aardvark", "Aardvark logged")
        let mealFood = food("meal-food", "Meal food")
        let catalogFood = food("catalog-banana", "Banana catalog")
        store.toggleFavorite(favorite)
        store.log(logged, amount: 1, unit: .serving, on: Date())
        store.saveMeal(
            name: "Apple meal",
            items: [MealItem(id: UUID(), food: mealFood, amount: 1, unit: .serving)]
        )

        let results = store.searchItems("a", catalogFoods: [catalogFood])

        XCTAssertEqual(results.prefix(2).map(searchResultName), ["Apple meal", "Zebra favorite"])
        XCTAssertEqual(results.dropFirst(2).map(searchResultName), ["Aardvark logged", "Banana catalog"])
        XCTAssertTrue(results.contains { item in
            if case let .meal(meal) = item { return meal.name == "Apple meal" }
            return false
        })
    }

    private func searchResultName(_ item: FoodPickerItem) -> String {
        switch item {
        case let .food(food): food.name
        case let .meal(meal): meal.name
        }
    }

    @MainActor
    func testCustomFoodsAndMealsRemainSeparatePersonalCatalogItems() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let americano = store.addCustomFood(
            name: "Americano",
            brand: "",
            calories: 5,
            carbs: 1,
            fat: 0,
            protein: 0,
            servingGrams: 355
        )
        store.saveMeal(
            name: "Coffee",
            items: [MealItem(id: UUID(), food: americano, amount: 1, unit: .serving, portionID: "custom-serving")]
        )
        store.saveMeal(
            name: "Breakfast",
            items: [MealItem(id: UUID(), food: americano, amount: 1, unit: .serving, portionID: "custom-serving")]
        )

        XCTAssertEqual(store.document.customFoods.count, 1)
        XCTAssertEqual(store.document.meals.count, 2)
        XCTAssertEqual(store.alphabetizedMeals.map(\.name), ["Breakfast", "Coffee"])

        store.deleteCustomFood(americano)
        XCTAssertTrue(store.document.customFoods.isEmpty)
        XCTAssertEqual(store.document.meals.count, 2)
    }

    @MainActor
    func testCustomFoodCanBeEditedAndUpdatesSavedReferences() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        let food = store.addCustomFood(
            name: "Original oats",
            brand: "Kitchen",
            calories: 100,
            carbs: 20,
            fat: 2,
            protein: 4,
            servingGrams: 40
        )
        store.log(food, amount: 1, unit: .serving, on: day)
        store.saveMeal(
            name: "Oats breakfast",
            items: [MealItem(id: UUID(), food: food, amount: 1, unit: .serving, portionID: "custom-serving")]
        )

        XCTAssertTrue(store.updateCustomFood(
            foodID: food.id,
            name: "Updated oats",
            brand: "New kitchen",
            calories: 150,
            carbs: 25,
            fat: 3,
            protein: 6,
            servingGrams: 50
        ))

        XCTAssertEqual(store.document.customFoods.first?.name, "Updated oats")
        XCTAssertEqual(store.document.customFoods.first?.nutrients.calories, 150)
        XCTAssertEqual(store.document.meals.first?.items.first?.food.name, "Updated oats")
        let loggedFood = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertEqual(loggedFood.food.name, "Updated oats")
        XCTAssertEqual(loggedFood.nutrients.calories, 150, accuracy: 0.001)

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.customFoods.first?.name, "Updated oats")
        XCTAssertEqual(reloaded.document.meals.first?.items.first?.food.name, "Updated oats")
    }

    @MainActor
    func testSavedMealCanBeEditedAndUpdatesLoggedMealEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        let toast = store.addCustomFood(
            name: "Toast",
            brand: "Bakery",
            calories: 100,
            carbs: 20,
            fat: 1,
            protein: 3,
            servingGrams: 40
        )
        let eggs = store.addCustomFood(
            name: "Eggs",
            brand: "Farm",
            calories: 140,
            carbs: 1,
            fat: 10,
            protein: 12,
            servingGrams: 100
        )
        let meal = try XCTUnwrap(store.saveMeal(
            name: "Old breakfast",
            items: [MealItem(id: UUID(), food: toast, amount: 1, unit: .serving, portionID: "custom-serving")]
        ))
        store.logMeal(meal, amount: 2, on: day)

        XCTAssertTrue(store.updateSavedMeal(
            mealID: meal.id,
            name: "New breakfast",
            items: [MealItem(id: UUID(), food: eggs, amount: 2, unit: .serving, portionID: "custom-serving")]
        ))

        XCTAssertEqual(store.document.meals.first?.name, "New breakfast")
        XCTAssertEqual(store.document.meals.first?.items.first?.food.name, "Eggs")
        let loggedMeal = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertEqual(loggedMeal.food.name, "New breakfast")
        XCTAssertEqual(loggedMeal.nutrients.calories, 560, accuracy: 0.001)
        XCTAssertEqual(loggedMeal.mealItems?.first?.food.name, "Eggs")

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.meals.first?.name, "New breakfast")
        let reloadedMeal = try XCTUnwrap(reloaded.entries(on: day).first)
        XCTAssertEqual(reloadedMeal.nutrients.calories, 560, accuracy: 0.001)
    }

    @MainActor
    func testReorderedDiaryEntriesPersistAndNewEntriesStayAtTop() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        func food(_ name: String) -> Food {
            Food(
                sourceID: name.lowercased(),
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: 100, carbs: 1, fat: 1, protein: 1),
                baseAmountGrams: 100,
                servingGrams: nil,
                servingDescription: nil
            )
        }

        store.log(food("A"), amount: 100, unit: .grams, on: day)
        store.log(food("B"), amount: 100, unit: .grams, on: day)
        store.log(food("C"), amount: 100, unit: .grams, on: day)

        let cID = try XCTUnwrap(store.entries(on: day).first { $0.food.name == "C" }?.id)
        let aID = try XCTUnwrap(store.entries(on: day).first { $0.food.name == "A" }?.id)
        store.moveEntry(cID, relativeTo: aID, placeAfterTarget: true, on: day)

        XCTAssertEqual(store.entries(on: day).map(\.food.name), ["B", "A", "C"])
        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["B", "A", "C"])

        reloaded.log(food("D"), amount: 100, unit: .grams, on: day)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["D", "B", "A", "C"])
    }

    @MainActor
    func testRepeatedMovesUpdateOrderAsAnEntryCrossesEachRow() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let day = Date()

        func food(_ name: String) -> Food {
            Food(
                sourceID: name,
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: 1, carbs: 0, fat: 0, protein: 0),
                baseAmountGrams: 1,
                servingGrams: nil,
                servingDescription: nil
            )
        }

        ["A", "B", "C", "D"].forEach { store.log(food($0), amount: 1, unit: .grams, on: day) }
        let dID = try XCTUnwrap(store.entries(on: day).first { $0.food.name == "D" }?.id)
        let cID = try XCTUnwrap(store.entries(on: day).first { $0.food.name == "C" }?.id)
        let bID = try XCTUnwrap(store.entries(on: day).first { $0.food.name == "B" }?.id)
        let aID = try XCTUnwrap(store.entries(on: day).first { $0.food.name == "A" }?.id)

        store.moveEntry(dID, relativeTo: cID, placeAfterTarget: true, on: day)
        XCTAssertEqual(store.entries(on: day).map(\.food.name), ["C", "D", "B", "A"])

        store.moveEntry(dID, relativeTo: bID, placeAfterTarget: true, on: day)
        XCTAssertEqual(store.entries(on: day).map(\.food.name), ["C", "B", "D", "A"])

        store.moveEntry(dID, relativeTo: aID, placeAfterTarget: true, on: day)
        XCTAssertEqual(store.entries(on: day).map(\.food.name), ["C", "B", "A", "D"])
    }

    @MainActor
    func testSavingAndBreakingApartMealPreservesDiaryAndTotals() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        func food(_ name: String, calories: Double) -> Food {
            Food(
                sourceID: name.lowercased(),
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: calories, carbs: calories / 10, fat: 1, protein: 2),
                baseAmountGrams: 100,
                servingGrams: nil,
                servingDescription: nil
            )
        }

        store.log(food("Toast", calories: 100), amount: 100, unit: .grams, on: day)
        store.log(food("Eggs", calories: 200), amount: 100, unit: .grams, on: day)
        store.log(food("Coffee", calories: 5), amount: 100, unit: .grams, on: day)
        let totalsBefore = store.totals(on: day)
        let entries = store.entries(on: day)
        let selectedIDs = Set(entries.filter { $0.food.name != "Coffee" }.map(\.id))

        store.saveMeal(name: "Breakfast", replacing: selectedIDs, on: day)

        let updatedEntries = store.entries(on: day)
        XCTAssertEqual(updatedEntries.map(\.food.name), ["Coffee", "Breakfast"])
        XCTAssertEqual(updatedEntries.last?.food.availablePortions.first?.label, "meal")
        XCTAssertEqual(updatedEntries.last?.savedMealID, store.document.meals.first?.id)
        XCTAssertEqual(store.document.meals.first?.items.count, 2)
        XCTAssertEqual(store.totals(on: day), totalsBefore)

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Coffee", "Breakfast"])
        XCTAssertEqual(reloaded.totals(on: day), totalsBefore)

        let mealEntryID = try XCTUnwrap(reloaded.entries(on: day).last?.id)
        reloaded.breakApartMeal(entryID: mealEntryID)

        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Coffee", "Eggs", "Toast"])
        XCTAssertTrue(reloaded.entries(on: day).allSatisfy { !$0.isMeal })
        XCTAssertEqual(reloaded.totals(on: day), totalsBefore)
        XCTAssertEqual(reloaded.document.meals.count, 1)

        let expandedReload = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(expandedReload.entries(on: day).map(\.food.name), ["Coffee", "Eggs", "Toast"])
        XCTAssertEqual(expandedReload.totals(on: day), totalsBefore)
    }

    @MainActor
    func testLoggingSavedMealCreatesOneBreakableDiaryEntry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        func food(_ name: String, calories: Double) -> Food {
            Food(
                sourceID: name.lowercased(),
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: calories, carbs: calories / 10, fat: 1, protein: 2),
                baseAmountGrams: 100,
                servingGrams: nil,
                servingDescription: nil
            )
        }

        store.log(food("Coffee", calories: 5), amount: 100, unit: .grams, on: day)
        store.saveMeal(
            name: "Breakfast",
            items: [
                MealItem(id: UUID(), food: food("Toast", calories: 100), amount: 100, unit: .grams),
                MealItem(id: UUID(), food: food("Eggs", calories: 200), amount: 100, unit: .grams)
            ]
        )
        let savedMeal = try XCTUnwrap(store.document.meals.first)

        store.logMeal(savedMeal, on: day)

        let loggedEntries = store.entries(on: day)
        XCTAssertEqual(loggedEntries.map(\.food.name), ["Breakfast", "Coffee"])
        let mealEntry = try XCTUnwrap(loggedEntries.first)
        XCTAssertTrue(mealEntry.isMeal)
        XCTAssertEqual(mealEntry.savedMealID, savedMeal.id)
        XCTAssertEqual(mealEntry.mealItems?.count, 2)
        XCTAssertEqual(mealEntry.nutrients.calories, 300)
        XCTAssertEqual(store.totals(on: day).calories, 305)

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Breakfast", "Coffee"])
        reloaded.breakApartMeal(entryID: mealEntry.id)

        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Toast", "Eggs", "Coffee"])
        XCTAssertTrue(reloaded.entries(on: day).allSatisfy { !$0.isMeal })
        XCTAssertEqual(reloaded.totals(on: day).calories, 305)
    }

    func testUnknownFoodSourceDecodesAsCustom() throws {
        let data = Data(#""retired-source""#.utf8)
        let source = try JSONDecoder().decode(FoodSource.self, from: data)
        XCTAssertEqual(source, .custom)
    }

    func testCatalogHasBothBundledSources() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = CatalogStore(url: projectRoot.appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))
        XCTAssertGreaterThan(catalog.count(source: .usda), 0)
        XCTAssertGreaterThan(catalog.count(source: .openFoodFacts), 0)
        XCTAssertFalse(catalog.search("banana", source: .usda).isEmpty)
        XCTAssertFalse(catalog.search("milk", source: .openFoodFacts).isEmpty)

        let combinedSources = Set(catalog.searchAll("milk", limit: 100).map(\.source))
        XCTAssertTrue(combinedSources.contains(.usda))
        XCTAssertTrue(combinedSources.contains(.openFoodFacts))
    }

    func testCatalogPreservesNaturalPortions() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = CatalogStore(url: projectRoot.appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))

        let scrambledEgg = try XCTUnwrap(
            catalog.search("egg whole cooked scrambled", source: .usda)
                .first { $0.name == "Egg, whole, cooked, scrambled" }
        )
        XCTAssertTrue(scrambledEgg.availablePortions.contains { $0.label == "large egg" && $0.grams == 61 })

        let butter = try XCTUnwrap(
            catalog.search("butter salted", source: .usda)
                .first { $0.availablePortions.contains { $0.label.localizedCaseInsensitiveContains("tablespoon") || $0.label == "tbsp" } }
        )
        XCTAssertNotNil(butter.availablePortions.first { $0.label.localizedCaseInsensitiveContains("table") || $0.label == "tbsp" })
    }

    @MainActor
    func testNewFoodsDefaultToOunces() {
        let previous = UserDefaults.standard.object(forKey: "defaultWeightUnit")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "defaultWeightUnit")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultWeightUnit")
            }
        }
        UserDefaults.standard.removeObject(forKey: "defaultWeightUnit")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let food = Food(
            sourceID: "cheddar",
            source: .usda,
            name: "Cheddar cheese",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 403, carbs: 1.3, fat: 33.1, protein: 24.9),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )

        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 1, unit: .ounces))
    }

    @MainActor
    func testQuickLogUsesDisplayedPreferenceAndFavoritesRemainAvailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let peanutButter = Food(
            sourceID: "peanut-butter",
            source: .usda,
            name: "Peanut butter",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 588, carbs: 20, fat: 50, protein: 25),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        let banana = Food(
            sourceID: "banana-suggestion",
            source: .usda,
            name: "Banana",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 89, carbs: 23, fat: 0.3, protein: 1.1),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        let preference = QuantityPreference(amount: 2, unit: .ounces)

        store.rememberPreference(preference, for: peanutButter)
        store.quickLog(peanutButter, on: Date())
        store.toggleFavorite(peanutButter)
        store.toggleFavorite(banana)

        let entry = try XCTUnwrap(store.entries(on: Date()).first)
        XCTAssertEqual(entry.amount, preference.amount)
        XCTAssertEqual(entry.unit, preference.unit)
        XCTAssertTrue(store.recentFoods.contains { $0.id == peanutButter.id })
        XCTAssertTrue(store.document.favorites.contains { $0.id == banana.id })
    }

    @MainActor
    func testRecentAndFrequentItemsMixSavedMealsWithFoods() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let toast = Food(
            sourceID: "mixed-toast",
            source: .custom,
            name: "Toast",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 20, fat: 1, protein: 3),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        store.saveMeal(
            name: "Breakfast",
            items: [MealItem(id: UUID(), food: toast, amount: 100, unit: .grams)]
        )
        let breakfast = try XCTUnwrap(store.document.meals.first)
        let day = Date()

        store.log(toast, amount: 100, unit: .grams, on: day)
        store.logMeal(breakfast, on: day)
        store.logMeal(breakfast, on: day)

        let oldFood = Food(
            sourceID: "old-frequent-food",
            source: .custom,
            name: "Old frequent food",
            brand: nil,
            barcode: nil,
            nutrients: .zero,
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )
        let oldDate = Calendar.current.date(byAdding: .day, value: -31, to: day) ?? day
        store.log(oldFood, amount: 100, unit: .grams, on: oldDate)

        XCTAssertEqual(store.recentItems.count, 3)
        XCTAssertTrue(store.recentItems.contains { if case .meal = $0 { true } else { false } })
        XCTAssertTrue(store.recentItems.contains { if case .food = $0 { true } else { false } })
        XCTAssertEqual(store.frequentItems.first?.id, "meal:\(breakfast.id.uuidString)")
        XCTAssertFalse(store.frequentItems.contains { $0.id == "food:\(oldFood.id)" })
    }

    @MainActor
    func testMealQuantityScalesMacrosAndConstituentFoodsWhenLoggedAndEdited() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)

        func food(_ name: String, calories: Double) -> Food {
            Food(
                sourceID: name.lowercased(),
                source: .custom,
                name: name,
                brand: nil,
                barcode: nil,
                nutrients: MacroNutrients(calories: calories, carbs: calories / 10, fat: 1, protein: 2),
                baseAmountGrams: 100,
                servingGrams: nil,
                servingDescription: nil
            )
        }

        store.saveMeal(
            name: "Double breakfast",
            items: [
                MealItem(id: UUID(), food: food("Toast", calories: 100), amount: 100, unit: .grams),
                MealItem(id: UUID(), food: food("Eggs", calories: 200), amount: 100, unit: .grams)
            ]
        )
        let meal = try XCTUnwrap(store.document.meals.first)

        store.logMeal(meal, amount: 2, on: day)

        let logged = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertEqual(logged.amount, 2)
        XCTAssertEqual(logged.nutrients.calories, 600, accuracy: 0.001)
        XCTAssertEqual(logged.mealItems?.map(\.amount) ?? [], [200, 200])

        store.updateMealEntry(entryID: logged.id, amount: 0.5)

        let edited = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertEqual(edited.amount, 0.5)
        XCTAssertEqual(edited.nutrients.calories, 150, accuracy: 0.001)
        XCTAssertEqual(edited.mealItems?.map(\.amount) ?? [], [50, 50])
        let reloadedEntry = try XCTUnwrap(DiaryStore(fileURL: fileURL).entries(on: day).first)
        XCTAssertEqual(reloadedEntry.nutrients.calories, 150, accuracy: 0.001)
    }

    @MainActor
    func testRenamingMealUpdatesSavedMealAndLoggedEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = DiaryStore(fileURL: fileURL)
        let food = Food(
            sourceID: "meal-rename-food",
            source: .custom,
            name: "Toast",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 20, fat: 1, protein: 3),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )

        store.saveMeal(
            name: "Old breakfast",
            items: [MealItem(id: UUID(), food: food, amount: 100, unit: .grams)]
        )
        let meal = try XCTUnwrap(store.document.meals.first)
        store.logMeal(meal, on: day)

        XCTAssertTrue(store.renameMeal(mealID: meal.id, name: "New breakfast"))
        XCTAssertEqual(store.document.meals.first?.name, "New breakfast")
        XCTAssertEqual(store.entries(on: day).first?.food.name, "New breakfast")
        XCTAssertEqual(DiaryStore(fileURL: fileURL).document.meals.first?.name, "New breakfast")
    }
}

extension CalorieTrackerTests {
    @MainActor
    func testPastDaysAutomaticallyBecomeGapOrThresholdCheatDays() throws {
        let calendar = testCalendar
        let days = (1...6).map { testDate(day: $0) }
        var document = DiaryDocument()
        document.dailyCalorieGoal = 2_000
        document.trackingStartDate = days[0]
        document.entries = [
            testEntry(calories: 1_600, date: days[0], name: "On target"),
            testEntry(calories: 1_499, date: days[2], name: "Under target"),
            testEntry(calories: 2_600, date: days[3], name: "Boundary"),
            testEntry(calories: 2_601, date: days[4], name: "Over target")
        ]
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("diary.json")

        let store = DiaryStore(
            document: document,
            fileURL: fileURL,
            calendar: calendar,
            referenceDate: days[5]
        )

        XCTAssertNil(store.status(on: days[0]))
        XCTAssertEqual(store.status(on: days[1])?.kind, .gap)
        XCTAssertEqual(store.status(on: days[2])?.kind, .cheat)
        XCTAssertNil(store.status(on: days[3]))
        XCTAssertEqual(store.status(on: days[4])?.kind, .cheat)
        XCTAssertTrue(store.document.dayStatuses.allSatisfy { $0.source == .automatic })
    }

    @MainActor
    func testNoGoalOnlyClassifiesEmptyPastDaysAsGaps() {
        let days = (1...4).map { testDate(day: $0) }
        var document = DiaryDocument()
        document.trackingStartDate = days[0]
        document.entries = [testEntry(calories: 20, date: days[0], name: "Snack")]
        let store = DiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: days[3]
        )

        XCTAssertNil(store.status(on: days[0]))
        XCTAssertEqual(store.status(on: days[1])?.kind, .gap)
        XCTAssertEqual(store.status(on: days[2])?.kind, .gap)
    }

    @MainActor
    func testLoggingFoodOnGapDayClearsGapStatus() {
        let yesterday = testDate(day: 1)
        let today = testDate(day: 2)
        var document = DiaryDocument()
        document.trackingStartDate = yesterday
        let store = DiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: today
        )
        XCTAssertEqual(store.status(on: yesterday)?.kind, .gap)

        store.log(testFood(calories: 300, name: "Breakfast"), amount: 1, unit: .serving, on: yesterday)

        XCTAssertNil(store.status(on: yesterday))
        XCTAssertEqual(store.entries(on: yesterday).count, 1)
    }

    @MainActor
    func testAlcoholQuickEntryUsesDefaultCaloriesAndPersists() throws {
        let day = testDate(day: 1)
        let fileURL = temporaryDiaryURL()
        let store = DiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        store.log(testFood(calories: 200, name: "Dinner"), amount: 1, unit: .serving, on: day)

        store.setAlcohol(drinks: 2, type: nil, on: day)

        let entry = try XCTUnwrap(store.alcoholEntry(on: day))
        XCTAssertEqual(entry.drinks, 2)
        XCTAssertNil(entry.type)
        XCTAssertEqual(entry.caloriesPerDrink, 150)
        XCTAssertEqual(store.totals(on: day).calories, 500, accuracy: 0.001)

        let reloaded = DiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        let reloadedEntry = try XCTUnwrap(reloaded.alcoholEntry(on: day))
        XCTAssertEqual(reloaded.document.schemaVersion, 6)
        XCTAssertEqual(reloadedEntry.id, entry.id)
        XCTAssertEqual(reloadedEntry.date, entry.date)
        XCTAssertEqual(reloadedEntry.drinks, entry.drinks)
        XCTAssertEqual(reloadedEntry.type, entry.type)
        XCTAssertEqual(reloadedEntry.loggedAt.timeIntervalSince(entry.loggedAt), 0, accuracy: 1)
        XCTAssertEqual(reloaded.totals(on: day).calories, 500, accuracy: 0.001)
    }

    @MainActor
    func testAlcoholQuickEntryKeepsOneTypeAndCanBeCleared() {
        let day = testDate(day: 1)
        let store = DiaryStore(
            document: DiaryDocument(),
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: day
        )

        store.setAlcohol(drinks: 1, type: .beer, on: day)
        let originalID = store.alcoholEntry(on: day)?.id
        store.setAlcohol(drinks: 3, type: .wine, on: day)

        XCTAssertEqual(store.document.alcoholEntries.count, 1)
        XCTAssertEqual(store.alcoholEntry(on: day)?.id, originalID)
        XCTAssertEqual(store.alcoholEntry(on: day)?.type, .wine)
        XCTAssertEqual(store.alcoholDrinkCount(on: day), 3)
        XCTAssertEqual(store.totals(on: day).calories, 375, accuracy: 0.001)

        store.setAlcohol(drinks: 0, type: .wine, on: day)

        XCTAssertNil(store.alcoholEntry(on: day))
        XCTAssertEqual(store.totals(on: day), .zero)
    }

    @MainActor
    func testLoggingAlcoholOnGapDayClearsGapStatus() {
        let yesterday = testDate(day: 1)
        let today = testDate(day: 2)
        var document = DiaryDocument()
        document.trackingStartDate = yesterday
        let store = DiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: today
        )
        XCTAssertEqual(store.status(on: yesterday)?.kind, .gap)

        store.setAlcohol(drinks: 1, type: .cocktail, on: yesterday)

        XCTAssertNil(store.status(on: yesterday))
        XCTAssertEqual(store.alcoholDrinkCount(on: yesterday), 1)
        XCTAssertEqual(store.totals(on: yesterday).calories, 200, accuracy: 0.001)
    }

    func testOlderDiaryDocumentsDecodeWithoutAlcoholEntries() throws {
        let data = try XCTUnwrap(#"{"schemaVersion":5}"#.data(using: .utf8))

        let document = try JSONDecoder().decode(DiaryDocument.self, from: data)

        XCTAssertEqual(document.schemaVersion, 5)
        XCTAssertTrue(document.alcoholEntries.isEmpty)
    }

    @MainActor
    func testManualCheatDayAdjustmentPersistsAndUndoPreservesFood() throws {
        let day = testDate(day: 1)
        let fileURL = temporaryDiaryURL()
        let store = DiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        store.log(testFood(calories: 450, name: "Breakfast"), amount: 1, unit: .serving, on: day)

        store.markCheatDay(on: day, adjustmentCalories: 1_000)

        XCTAssertEqual(store.status(on: day)?.kind, .cheat)
        XCTAssertEqual(store.status(on: day)?.source, .manual)
        XCTAssertEqual(store.status(on: day)?.adjustmentCalories, 1_000)
        XCTAssertEqual(store.totals(on: day).calories, 1_450, accuracy: 0.001)
        XCTAssertEqual(store.entries(on: day).filter(\.isCheatDayAdjustment).count, 1)

        store.markCheatDay(on: day, adjustmentCalories: 1_500)

        XCTAssertEqual(store.status(on: day)?.adjustmentCalories, 1_500)
        XCTAssertEqual(store.totals(on: day).calories, 1_950, accuracy: 0.001)
        XCTAssertEqual(store.entries(on: day).filter(\.isCheatDayAdjustment).count, 1)
        let reloaded = DiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        XCTAssertEqual(reloaded.status(on: day)?.adjustmentCalories, 1_500)

        reloaded.undoCheatDay(on: day)

        XCTAssertNil(reloaded.status(on: day))
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Breakfast"])
        XCTAssertEqual(reloaded.totals(on: day).calories, 450, accuracy: 0.001)
    }

    @MainActor
    func testStreakSummaryUsesConsecutiveLoggedDaysAndStopsAtCheatDay() {
        let days = (1...3).map { testDate(day: $0) }
        var document = DiaryDocument()
        document.trackingStartDate = days[0]
        document.entries = [
            testEntry(calories: 1_800, date: days[0], name: "Toast"),
            testEntry(calories: 2_000, date: days[1], name: "Toast")
        ]
        let store = DiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: days[2]
        )

        let summary = store.streak(referenceDate: days[2])
        XCTAssertEqual(summary.dayCount, 2)
        XCTAssertEqual(summary.averageNutrients.calories, 1_900, accuracy: 0.001)
        XCTAssertEqual(summary.minimumNutrients.calories, 1_800, accuracy: 0.001)
        XCTAssertEqual(summary.maximumNutrients.calories, 2_000, accuracy: 0.001)
        XCTAssertEqual(summary.mostPopularItem, "Toast")

        store.markCheatDay(on: days[1])
        XCTAssertEqual(store.streak(referenceDate: days[2]).dayCount, 0)
    }

    func testFoodWeightReportExpandsMealSnapshotsAndFormatsShareableMarkdown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(month: Int, day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        func food(_ id: String, _ name: String, brand: String? = nil, servingGrams: Double) -> Food {
            Food(
                sourceID: id,
                source: .custom,
                name: name,
                brand: brand,
                barcode: nil,
                nutrients: .zero,
                baseAmountGrams: servingGrams,
                servingGrams: servingGrams,
                servingDescription: "1 serving",
                portions: [FoodPortion(id: "serving", label: "serving", grams: servingGrams)]
            )
        }
        func entry(
            food: Food,
            amount: Double,
            unit: LogUnit,
            date: Date,
            kind: DiaryEntryKind? = nil
        ) -> DiaryEntry {
            DiaryEntry(
                id: UUID(),
                date: calendar.startOfDay(for: date),
                food: food,
                amount: amount,
                unit: unit,
                nutrients: .zero,
                loggedAt: date,
                portionID: unit == .serving ? "serving" : nil,
                kind: kind
            )
        }

        let ounce = 28.349_523_125
        let almondMilk = food("almond-milk", "Almond milk", servingGrams: ounce)
        let banana = food("banana", "Banana", servingGrams: ounce * 2)
        let wholeMilk = food("whole-milk", "Whole Milk", brand: "Great Value", servingGrams: ounce)
        let mealID = UUID()
        let mealSnapshot = [
            MealItem(id: UUID(), food: almondMilk, amount: 1, unit: .ounces),
            MealItem(id: UUID(), food: banana, amount: 1, unit: .serving, portionID: "serving"),
            MealItem(id: UUID(), food: wholeMilk, amount: 0.51, unit: .serving, portionID: "serving")
        ]
        let mealFood = food("meal", "Breakfast", servingGrams: 1)
        let mealEntry = DiaryEntry(
            id: UUID(),
            date: calendar.startOfDay(for: date(month: 8, day: 24)),
            food: mealFood,
            amount: 1,
            unit: .serving,
            nutrients: .zero,
            loggedAt: date(month: 8, day: 24),
            savedMealID: mealID,
            mealItems: mealSnapshot
        )
        let replacementFood = food("replacement", "Current recipe only", servingGrams: ounce * 100)
        var document = DiaryDocument()
        document.meals = [SavedMeal(
            id: mealID,
            name: "Breakfast",
            items: [MealItem(id: UUID(), food: replacementFood, amount: 1, unit: .serving, portionID: "serving")]
        )]
        document.entries = [
            entry(food: almondMilk, amount: 2, unit: .ounces, date: date(month: 8, day: 3)),
            mealEntry,
            entry(food: almondMilk, amount: 100, unit: .ounces, date: date(month: 5, day: 26)),
            entry(
                food: almondMilk,
                amount: 100,
                unit: .ounces,
                date: date(month: 8, day: 24),
                kind: .cheatDayAdjustment
            )
        ]

        let report = FoodWeightReport(
            document: document,
            calendar: calendar,
            referenceDate: date(month: 8, day: 24)
        )

        XCTAssertEqual(report.coverageDescription, "August 3–August 24, 2026")
        XCTAssertEqual(report.items.map(\.name), ["Almond milk", "Banana", "Whole Milk — Great Value"])
        XCTAssertEqual(report.items.map(\.wholeOunces), [3, 2, 1])
        XCTAssertFalse(report.markdown.contains("| Rank |"))
        XCTAssertFalse(report.markdown.contains("Total logged food weight"))
        XCTAssertFalse(report.markdown.contains("Report window"))
        XCTAssertFalse(report.markdown.contains("## Method"))
        XCTAssertTrue(report.markdown.hasSuffix("| Whole Milk — Great Value | 1 oz |\n"))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = try report.writeShareFile(in: directory)
        XCTAssertEqual(fileURL.lastPathComponent, "foods-by-total-weight-last-90-days.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), report.markdown)
    }

    func testFoodWeightReportUsesSavedMealAsFallbackWithoutHistoricalSnapshot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
        let ounce = 28.349_523_125
        let food = Food(
            sourceID: "fallback-food",
            source: .custom,
            name: "Fallback food",
            brand: nil,
            barcode: nil,
            nutrients: .zero,
            baseAmountGrams: ounce,
            servingGrams: ounce,
            servingDescription: "1 serving",
            portions: [FoodPortion(id: "serving", label: "serving", grams: ounce)]
        )
        let mealID = UUID()
        let meal = SavedMeal(
            id: mealID,
            name: "Legacy meal",
            items: [MealItem(id: UUID(), food: food, amount: 1, unit: .serving, portionID: "serving")]
        )
        let mealFood = Food(
            sourceID: "meal",
            source: .custom,
            name: meal.name,
            brand: nil,
            barcode: nil,
            nutrients: .zero,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 meal"
        )
        var document = DiaryDocument()
        document.meals = [meal]
        document.entries = [DiaryEntry(
            id: UUID(),
            date: day,
            food: mealFood,
            amount: 2,
            unit: .serving,
            nutrients: .zero,
            loggedAt: day,
            savedMealID: mealID
        )]

        let report = FoodWeightReport(document: document, calendar: calendar, referenceDate: day)

        XCTAssertEqual(report.items.map(\.name), ["Fallback food"])
        XCTAssertEqual(report.items.map(\.wholeOunces), [2])
    }

    func testCustomFoodFileLoadsAndCreatesOneServingFood() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("calfood")
        let json = """
        {
          "format": "calorie-tracker-food",
          "version": 1,
          "name": "  Buffalo chicken salad  ",
          "servingDescription": "whole bowl",
          "servingGrams": 510,
          "nutrition": {
            "calories": 750,
            "carbohydratesGrams": 32,
            "fatGrams": 40,
            "proteinGrams": 60
          },
          "notes": "  Dressing is the biggest uncertainty.  "
        }
        """
        try Data(json.utf8).write(to: fileURL)

        let importedFile = try CustomImportFile.load(from: fileURL)
        guard case let .food(file) = importedFile else {
            return XCTFail("Expected a food file")
        }
        let food = file.food.makeFood(sourceID: "import-test")

        XCTAssertEqual(file.name, "Buffalo chicken salad")
        XCTAssertEqual(file.notes, "Dressing is the biggest uncertainty.")
        XCTAssertEqual(food.nutrients.calories, 750)
        XCTAssertEqual(food.nutrients.carbs, 32)
        XCTAssertEqual(food.nutrients.fat, 40)
        XCTAssertEqual(food.nutrients.protein, 60)
        XCTAssertEqual(food.servingGrams, 510)
        XCTAssertEqual(food.availablePortions.first?.label, "whole bowl")
        XCTAssertEqual(food.nutrients(for: 1, unit: .serving, portionID: "imported-serving"), food.nutrients)
    }

    @MainActor
    func testOneOffImportedFoodLogsWithoutSavingCustomFood() throws {
        let fileURL = temporaryDiaryURL()
        let store = DiaryStore(fileURL: fileURL)
        let importedFood = CustomFoodDefinition(
            name: "Quinoa chicken bowl",
            servingDescription: "whole bowl",
            servingGrams: 620,
            nutrition: CustomFoodDefinition.Nutrition(
                calories: 900,
                carbohydratesGrams: 95,
                fatGrams: 28,
                proteinGrams: 70
            ),
            notes: nil
        )

        let food = importedFood.makeFood(sourceID: "one-off-import")
        store.log(food, amount: 1, unit: .serving, portionID: "imported-serving", on: Date())

        XCTAssertTrue(store.document.customFoods.isEmpty)
        XCTAssertEqual(store.entries(on: Date()).map(\.food.name), ["Quinoa chicken bowl"])
        XCTAssertEqual(store.totals(on: Date()).calories, 900)
    }

    func testCustomMealFileLoadsAListOfFoodsAndCalculatesTotals() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("calmeal")
        let json = """
        {
          "format": "calorie-tracker-meal",
          "version": 1,
          "name": "Chicken and rice",
          "foods": [
            {
              "name": "Chicken",
              "servingDescription": "6 oz portion",
              "servingGrams": 170,
              "nutrition": {
                "calories": 300,
                "carbohydratesGrams": 0,
                "fatGrams": 12,
                "proteinGrams": 45
              }
            },
            {
              "name": "Rice",
              "servingDescription": "1 cup",
              "servingGrams": 190,
              "nutrition": {
                "calories": 240,
                "carbohydratesGrams": 52,
                "fatGrams": 1,
                "proteinGrams": 5
              }
            }
          ],
          "notes": "Estimated from the plate."
        }
        """
        try Data(json.utf8).write(to: fileURL)

        let importedFile = try CustomImportFile.load(from: fileURL)
        guard case let .meal(file) = importedFile else {
            return XCTFail("Expected a meal file")
        }
        let meal = file.makeMeal()

        XCTAssertEqual(meal.name, "Chicken and rice")
        XCTAssertEqual(meal.items.map(\.food.name), ["Chicken", "Rice"])
        XCTAssertEqual(meal.items.map(\.food.servingGrams), [170, 190])
        XCTAssertEqual(meal.nutrients, MacroNutrients(calories: 540, carbs: 52, fat: 13, protein: 50))
    }

    @MainActor
    func testOneOffImportedMealIsBreakableWithoutSavingMealOrFoods() throws {
        let store = DiaryStore(fileURL: temporaryDiaryURL())
        let importedMeal = CustomMealFile(
            format: CustomMealFile.formatIdentifier,
            version: CustomMealFile.currentVersion,
            name: "Chicken and rice",
            foods: [
                CustomFoodDefinition(
                    name: "Chicken",
                    servingDescription: "portion",
                    servingGrams: 170,
                    nutrition: CustomFoodDefinition.Nutrition(
                        calories: 300,
                        carbohydratesGrams: 0,
                        fatGrams: 12,
                        proteinGrams: 45
                    ),
                    notes: nil
                ),
                CustomFoodDefinition(
                    name: "Rice",
                    servingDescription: "cup",
                    servingGrams: 190,
                    nutrition: CustomFoodDefinition.Nutrition(
                        calories: 240,
                        carbohydratesGrams: 52,
                        fatGrams: 1,
                        proteinGrams: 5
                    ),
                    notes: nil
                )
            ],
            notes: nil
        )

        store.logOneOffMeal(importedMeal.makeMeal(), on: Date())

        let mealEntry = try XCTUnwrap(store.entries(on: Date()).first)
        XCTAssertTrue(mealEntry.isMeal)
        XCTAssertNil(mealEntry.savedMealID)
        XCTAssertEqual(mealEntry.mealItems?.map(\.food.name), ["Chicken", "Rice"])
        XCTAssertTrue(store.document.meals.isEmpty)
        XCTAssertTrue(store.document.customFoods.isEmpty)
        XCTAssertEqual(store.totals(on: Date()).calories, 540)

        store.breakApartMeal(entryID: mealEntry.id)
        XCTAssertEqual(store.entries(on: Date()).map(\.food.name), ["Chicken", "Rice"])
    }

    func testFoodAndMealFormatsRequireTheirMatchingExtensions() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("calmeal")
        let json = """
        {
          "format": "calorie-tracker-food",
          "version": 1,
          "name": "Food with wrong extension",
          "servingDescription": "serving",
          "servingGrams": 100,
          "nutrition": {
            "calories": 100,
            "carbohydratesGrams": 10,
            "fatGrams": 2,
            "proteinGrams": 5
          }
        }
        """
        try Data(json.utf8).write(to: fileURL)

        XCTAssertThrowsError(try CustomImportFile.load(from: fileURL)) { error in
            XCTAssertEqual(error as? CustomImportError, .extensionMismatch(expected: "calfood"))
        }
    }

    func testCustomFoodFileRejectsUnsupportedVersion() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("calfood")
        let json = """
        {
          "format": "calorie-tracker-food",
          "version": 99,
          "name": "Future food",
          "servingDescription": "serving",
          "servingGrams": 100,
          "nutrition": {
            "calories": 100,
            "carbohydratesGrams": 10,
            "fatGrams": 2,
            "proteinGrams": 5
          }
        }
        """
        try Data(json.utf8).write(to: fileURL)

        XCTAssertThrowsError(try CustomImportFile.load(from: fileURL)) { error in
            XCTAssertEqual(error as? CustomImportError, .unsupportedVersion(99))
        }
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDate(day: Int) -> Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 7, day: day))!
    }

    private func temporaryDiaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("diary.json")
    }

    private func testFood(calories: Double, name: String) -> Food {
        Food(
            sourceID: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            source: .custom,
            name: name,
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: calories, carbs: calories / 20, fat: calories / 100, protein: calories / 25),
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 serving",
            portions: [FoodPortion(id: "serving", label: "serving", grams: 1)]
        )
    }

    private func testEntry(calories: Double, date: Date, name: String) -> DiaryEntry {
        let food = testFood(calories: calories, name: name)
        return DiaryEntry(
            id: UUID(),
            date: date,
            food: food,
            amount: 1,
            unit: .serving,
            nutrients: food.nutrients,
            loggedAt: date,
            portionID: "serving"
        )
    }
}
