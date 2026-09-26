import Combine
import XCTest
@testable import CalorieTracker

final class CalorieTrackerTests: XCTestCase {
    func testSnackSuggestionsFilterAllFocusCombinationsAndAlwaysIncludeProtein() {
        XCTAssertEqual(Set(SnackSuggestions.library.map(\.id)).count, SnackSuggestions.library.count)
        for mask in 0..<16 {
            let preferences = SnackFocusPreferences(fiber: mask & 1 != 0, processedMeat: mask & 2 != 0,
                                                    redMeat: mask & 4 != 0, alcohol: mask & 8 != 0)
            let snacks = SnackSuggestions.snacks(for: preferences)
            let enabledAreas = SnackFocusArea.allCases.filter(preferences.includes)
            XCTAssertFalse(snacks.isEmpty)
            XCTAssertTrue(snacks.contains { $0.reasons[.protein] != nil })
            XCTAssertTrue(snacks.allSatisfy { snack in
                enabledAreas.contains { snack.reasons[$0] != nil }
                    && !snack.containsProcessedMeat
                    && !snack.containsRedMeat
            })
            if preferences.fiber {
                XCTAssertTrue(snacks.contains { $0.id == "almonds" })
            }
        }
    }

    func testSnackMeatExclusionsApplyToEverySectionIndependently() {
        let reasons = Dictionary(uniqueKeysWithValues: SnackFocusArea.allCases.map { ($0, "Test reason") })
        let candidates = [
            SnackSuggestion(id: "plant", name: "Plant", servingTip: "", reasons: reasons),
            SnackSuggestion(id: "red", name: "Red", servingTip: "", reasons: reasons, containsRedMeat: true),
            SnackSuggestion(id: "processed", name: "Processed", servingTip: "", reasons: reasons, containsProcessedMeat: true),
            SnackSuggestion(id: "both", name: "Both", servingTip: "", reasons: reasons, containsProcessedMeat: true, containsRedMeat: true)
        ]
        for (processed, red, allowed) in [
            (false, false, ["plant", "red", "processed", "both"]),
            (true, false, ["plant", "red"]),
            (false, true, ["plant", "processed"]),
            (true, true, ["plant"])
        ] {
            let snacks = SnackSuggestions.snacks(for: .init(fiber: true, processedMeat: processed, redMeat: red, alcohol: true), candidates: candidates)
            XCTAssertEqual(snacks.map(\.id), allowed)
        }
    }

    func testSnackSelectionPreservesUniqueFilteredListAndDropsHiddenChoices() {
        let all = SnackSuggestions.snacks(for: .init(fiber: true, processedMeat: true, redMeat: true, alcohol: true))
        let ids = Set(SnackSuggestions.library.map(\.id))
        let selected = SnackSuggestions.selectedSnacks(in: all, ids: ids)
        XCTAssertEqual(selected.count, ids.count)
        XCTAssertEqual(Set(selected.map(\.id)), ids)
        let protein = SnackSuggestions.snacks(for: .init(fiber: false, processedMeat: false, redMeat: false, alcohol: false))
        XCTAssertEqual(SnackSuggestions.selectedSnacks(in: protein, ids: ids).map(\.id), protein.map(\.id))
        XCTAssertTrue(SnackSuggestions.selectedSnacks(in: all, ids: []).isEmpty)
        for snack in selected { XCTAssertEqual(VitaChaseDeepLink(url: snack.reminderURL), .logFood) }
    }

    @MainActor
    func testSnackRemindersRememberExplicitListWithoutRequestingAccessOnOpen() async {
        let defaults = snackTestDefaults()
        let client = TestSnackRemindersClient()
        let store = SnackRemindersStore(client: client, defaults: defaults)
        store.refreshLists()
        XCTAssertEqual(client.accessRequests, 0)
        XCTAssertNil(store.selectedList)
        let prepared = await store.prepareListChoice()
        XCTAssertTrue(prepared)
        XCTAssertNil(store.selectedList, "Never automatically choose a destination")
        store.choose(client.availableLists[1])
        XCTAssertTrue(client.savedBatches.isEmpty, "Choosing a list must not write reminders")

        let reopened = SnackRemindersStore(client: client, defaults: defaults)
        XCTAssertEqual(reopened.selectedList, client.availableLists[1])
        client.availableLists[1] = .init(id: "groceries", title: "Weekly Groceries", account: "iCloud")
        reopened.refreshLists()
        XCTAssertEqual(reopened.selectedList?.title, "Weekly Groceries")
        XCTAssertEqual(client.accessRequests, 1)
        let added = await reopened.add([SnackSuggestions.library[0]])
        XCTAssertTrue(added)
        XCTAssertEqual(client.fetchedListIDs, ["groceries"])
        XCTAssertEqual(client.savedBatches.first?.listID, "groceries")
        XCTAssertEqual(client.savedBatches.first?.snacks.map(\.id), ["greek-yogurt"])
        XCTAssertNotNil(reopened.statusMessage)
        XCTAssertFalse(reopened.isBusy)
    }

    @MainActor
    func testSnackRemindersSkipIncompleteTitleAndIdentityMatchesAndAllowRestocking() async {
        let client = TestSnackRemindersClient()
        let store = SnackRemindersStore(client: client, defaults: snackTestDefaults())
        _ = await store.prepareListChoice()
        store.choose(client.availableLists[1])
        let yogurt = SnackSuggestions.library[0]
        let cottage = SnackSuggestions.library[1]
        let eggs = SnackSuggestions.library[2]
        client.existing["groceries"] = [
            .init(title: "  PLAIN   GREEK YOGURT \n", url: nil),
            .init(title: "Renamed by user", url: cottage.reminderURL)
        ]
        let added = await store.add([yogurt, cottage, eggs, eggs])
        XCTAssertTrue(added)
        XCTAssertEqual(client.savedBatches.count, 1)
        XCTAssertEqual(client.savedBatches[0].snacks.map(\.id), [eggs.id])
        let repeated = await store.add([yogurt, cottage, eggs])
        XCTAssertTrue(repeated)
        XCTAssertEqual(client.savedBatches.count, 1)
        XCTAssertEqual(store.statusMessage, "These snacks are already on Groceries.")

        // Completed/deleted reminders no longer appear in the incomplete query.
        client.existing["groceries"] = []
        let restocked = await store.add([eggs])
        XCTAssertTrue(restocked)
        XCTAssertEqual(client.savedBatches.count, 2)
    }

    @MainActor
    func testSnackRemindersMissingListDoesNotFallBackAndCanBeChanged() async {
        let client = TestSnackRemindersClient()
        let store = SnackRemindersStore(client: client, defaults: snackTestDefaults())
        _ = await store.prepareListChoice()
        store.choose(client.availableLists[1])
        client.availableLists.removeLast() // Also models a list becoming read-only.
        let added = await store.add([SnackSuggestions.library[0]])
        XCTAssertFalse(added)
        XCTAssertEqual(store.selectedList?.id, "groceries")
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.statusMessage)
        XCTAssertTrue(client.savedBatches.isEmpty)
        XCTAssertTrue(client.fetchedListIDs.isEmpty)
        _ = await store.prepareListChoice()
        store.choose(client.availableLists[0])
        let retried = await store.add([SnackSuggestions.library[0]])
        XCTAssertTrue(retried)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(client.savedBatches.first?.listID, "personal")
    }

    @MainActor
    func testSnackRemindersDeniedEmptyAndFailedRequestsNeverReportSuccess() async {
        let client = TestSnackRemindersClient()
        let store = SnackRemindersStore(client: client, defaults: snackTestDefaults())
        let empty = await store.add([])
        XCTAssertFalse(empty)
        XCTAssertEqual(client.accessRequests, 0)
        client.accessError = SnackRemindersError.accessDenied
        let denied = await store.prepareListChoice()
        XCTAssertFalse(denied)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.lists.isEmpty)
        client.accessError = nil
        _ = await store.prepareListChoice()
        store.choose(client.availableLists[1])
        client.fetchError = SnackRemindersError.fetchFailed
        let fetchFailed = await store.add([SnackSuggestions.library[0]])
        XCTAssertFalse(fetchFailed)
        XCTAssertTrue(client.savedBatches.isEmpty)
        XCTAssertNil(store.statusMessage)
        client.fetchError = nil
        client.saveError = CocoaError(.fileWriteUnknown)
        let saveFailed = await store.add([SnackSuggestions.library[0]])
        XCTAssertFalse(saveFailed)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.statusMessage)
        XCTAssertFalse(store.isBusy)
        client.saveError = nil
        let retried = await store.add([SnackSuggestions.library[0]])
        XCTAssertTrue(retried)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(client.savedBatches.count, 1)
    }

    @MainActor
    func testSnackRemindersIgnoreRepeatedAddWhileARequestIsInFlight() async {
        let client = TestSnackRemindersClient()
        let store = SnackRemindersStore(client: client, defaults: snackTestDefaults())
        _ = await store.prepareListChoice()
        store.choose(client.availableLists[1])
        let snacks = [SnackSuggestions.library[0]]
        client.onFetch = {
            XCTAssertTrue(store.isBusy)
            let repeated = await store.add(snacks)
            XCTAssertFalse(repeated)
            store.choose(client.availableLists[0])
            XCTAssertEqual(store.selectedList?.id, "groceries")
        }
        let added = await store.add(snacks)
        XCTAssertTrue(added)
        XCTAssertEqual(client.savedBatches.count, 1)
        XCTAssertEqual(client.fetchedListIDs, ["groceries"])
        client.onFetch = nil
    }

    private func snackTestDefaults() -> UserDefaults {
        let suite = "snack-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testYumChaseBrandingPreservesInstallationAndWidgetIdentity() throws {
        let app = Bundle.main
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Yum Chase")
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CFBundleName") as? String, "Yum Chase")
        XCTAssertEqual(app.bundleIdentifier, "com.cseibert.CalorieTracker")
        XCTAssertEqual(SharedDiaryStorage.appGroupIdentifier, "group.com.cseibert.CalorieTracker")
        XCTAssertEqual(SharedDiaryStorage.widgetKind, "VitaChaseQuickLog")
        XCTAssertEqual(SharedDiaryStorage.caloriesWidgetKind, "VitaChaseCaloriesLeft")
        XCTAssertEqual(VitaChaseDeepLink.logFoodURL.absoluteString, "vitachase://log-food")

        let widgetsURL = try XCTUnwrap(app.builtInPlugInsURL).appendingPathComponent("VitaChaseWidgets.appex")
        let widgets = try XCTUnwrap(Bundle(url: widgetsURL))
        XCTAssertEqual(widgets.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Yum Chase Widgets")
        XCTAssertEqual(widgets.bundleIdentifier, "com.cseibert.CalorieTracker.Widgets")

        let icons = try XCTUnwrap(app.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primaryIcon = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primaryIcon["CFBundleIconName"] as? String, "AppIcon")
    }

    func testAppIconUsesTheApprovedPeachMochiArtwork() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let selected = root.appendingPathComponent("docs/icon-concepts/2026-09-02-round-2/yum-chase-01-peach-mochi.png")
        let appIcon = root.appendingPathComponent("CalorieTracker/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
        XCTAssertEqual(try Data(contentsOf: appIcon), try Data(contentsOf: selected))
    }

    private var resolutionCatalog: CatalogStore {
        CatalogStore(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))
    }

    func testImportedBaconResolvesAndSurvivesSQLiteAndQuickLogging() throws {
        let json = #"{"format":"calorie-tracker-meal","version":1,"name":"White Bean, Kale & Pasta Soup with Bacon","foods":[{"name":"Bacon","servingDescription":"3/4 slice, cooked and chopped","servingGrams":12,"nutrition":{"calories":32,"carbohydratesGrams":0.1,"fatGrams":2.5,"proteinGrams":2.3,"fiberGrams":0}},{"name":"White beans","servingDescription":"1/4 can","servingGrams":64,"nutrition":{"calories":73,"carbohydratesGrams":12.8,"fatGrams":0.3,"proteinGrams":4.8,"fiberGrams":3.5}}]}"#
        let file = try JSONDecoder().decode(CustomMealFile.self, from: Data(json.utf8))
        let meal = file.makeMeal()
        XCTAssertNil(meal.items[0].food.containsProcessedMeat)
        let url = temporaryDiaryURL()
        let day = testDate(day: 1)
        let repository = try DiaryRepository(fileURL: url, calendar: testCalendar, catalog: resolutionCatalog)
        let saved = try repository.performSync(scope: .day(day)) { try $0.logImportedMeal(meal, on: day) }
        let bacon = saved.items[0].food
        XCTAssertEqual(bacon.containsProcessedMeat, true)
        XCTAssertEqual(bacon.containsRedMeat, false)
        XCTAssertEqual(bacon.meatResolution?.processed, .catalog)
        XCTAssertEqual(bacon.id, meal.items[0].food.id)
        XCTAssertEqual(bacon.nutrients, meal.items[0].food.nutrients)
        XCTAssertEqual(bacon.servingGrams, 12)
        XCTAssertEqual(bacon.portions, meal.items[0].food.portions)
        let reopened = try DiaryRepository(fileURL: url, calendar: testCalendar, catalog: resolutionCatalog)
        var snapshot = try reopened.snapshotSync().document
        XCTAssertEqual(snapshot.entries[0].mealItems, saved.items)
        let next = testDate(day: 2)
        let result = try reopened.performSync(scope: .window(reference: next, selectedDay: nil)) {
            $0.logQuickSelection("meal:" + saved.id.uuidString, on: next)
        }
        XCTAssertNotNil(result)
        snapshot = try repository.snapshotSync().document
        let engine = DiaryEngine(document: snapshot, calendar: testCalendar)
        XCTAssertEqual(engine.weeklyMeatDays(numberOfDays: 2, referenceDate: next).map(\.processedMeatDays).reduce(0, +), 2)
        XCTAssertEqual(engine.meatDayFoods(numberOfDays: 1, referenceDate: day).first?.processedMeatFoods,
                       [meal.name + " — Bacon"])
        XCTAssertEqual(snapshot.entries[0].nutrients, meal.nutrients)
    }

    func testResolverHandlesUnknownsQualifiersAndPerFlagOverrides() throws {
        let resolver = FoodResolver(catalog: resolutionCatalog)
        for (name, processed, red) in [("Bacon", true, false), ("Turkey bacon", true, false),
                                      ("Bacon, meatless", false, false), ("vegan bacon", false, false),
                                      ("Beef broth", false, false)] {
            let resolved = resolver.resolve(testFood(calories: 12, name: name))
            XCTAssertEqual(resolved.containsProcessedMeat, processed, name)
            XCTAssertEqual(resolved.containsRedMeat, red, name)
        }
        for name in ["House special", "Soup without bacon", "Bacon flavored seasoning"] {
            XCTAssertNil(FoodResolver(catalog: nil).resolve(testFood(calories: 12, name: name)).containsProcessedMeat, name)
        }
        var imported = CustomFoodDefinition(name: "Bacon", servingDescription: "slice", servingGrams: 12,
            nutrition: .init(calories: 32, carbohydratesGrams: 0.1, fatGrams: 2.5, proteinGrams: 2.3),
            notes: nil, containsProcessedMeat: false)
        var resolved = resolver.resolve(imported.makeFood())
        XCTAssertEqual(resolved.containsProcessedMeat, false)
        XCTAssertEqual(resolved.containsRedMeat, false)
        XCTAssertEqual(resolved.meatResolution?.processed, .imported)
        XCTAssertEqual(resolver.suggestion(for: resolved).containsProcessedMeat, true)
        imported.processedMeatWasEdited = true
        resolved = resolver.resolve(imported.makeFood())
        XCTAssertEqual(resolved.meatResolution?.processed, .user)
        XCTAssertEqual(resolved.containsProcessedMeat, false)
        // Review-only provenance cannot be forged in an imported file.
        let encoded = try JSONEncoder().encode(imported)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("WasEdited"))
        var legacy = testFood(calories: 12, name: "Bacon")
        legacy.containsProcessedMeat = false
        legacy.containsRedMeat = false
        XCTAssertEqual(resolver.resolve(legacy), legacy)
    }

    func testResolverDoesNotConfuseIngredientMatchingWithExactIdentity() {
        let resolver = FoodResolver(catalog: resolutionCatalog)
        let bacon = resolver.resolve(testFood(calories: 32, name: "Bacon"))
        XCTAssertNil(bacon.meatResolution?.matchedFoodID, "Generic bacon has multiple preparations.")
        var exact = testFood(calories: 32, name: "Pork, cured, bacon, cooked, restaurant")
        exact = resolver.resolve(exact)
        XCTAssertEqual(exact.meatResolution?.matchedFoodID, "usda:749420")
        XCTAssertEqual(exact.source, .custom)
        XCTAssertEqual(exact.nutrients.calories, 32)
        let unknown = resolver.resolve(testFood(calories: 12, name: "House special"))
        XCTAssertNil(unknown.meatResolution?.matchedFoodID)
        XCTAssertNil(unknown.containsProcessedMeat)
        XCTAssertNil(unknown.containsRedMeat)
    }

    func testManualFoodAutomaticClassificationAndUserOverrideSurviveEdits() throws {
        let engine = DiaryEngine(document: DiaryDocument(), catalog: resolutionCatalog)
        let food = engine.addCustomFood(name: "Bacon", brand: "", calories: 32, carbs: 0.1, fat: 2.5,
                                       protein: 2.3, servingGrams: 12)
        XCTAssertEqual(food.containsProcessedMeat, true)
        XCTAssertTrue(engine.updateCustomFood(foodID: food.id, name: "Bacon", brand: "", calories: 32,
            carbs: 0.1, fat: 2.5, protein: 2.3, servingGrams: 12,
            meatOverrides: FoodMeatOverrides(processed: false, red: nil)))
        XCTAssertEqual(engine.document.customFoods[0].containsProcessedMeat, false)
        XCTAssertEqual(engine.document.customFoods[0].meatResolution?.processed, .user)
        XCTAssertTrue(engine.updateCustomFood(foodID: food.id, name: "Bacon", brand: "", calories: 32,
            carbs: 0.1, fat: 2.5, protein: 2.3, servingGrams: 12,
            meatOverrides: FoodMeatOverrides(processed: nil, red: nil)))
        XCTAssertEqual(engine.document.customFoods[0].containsProcessedMeat, true)
        let renamed = engine.document.customFoods[0]
        var vegan = renamed
        vegan.name = "Vegan bacon"
        XCTAssertEqual(FoodResolver(catalog: nil).resolve(vegan).containsProcessedMeat, false)
    }

    func testMealResolutionRecomputesIngredientsButKeepsExplicitOverrides() throws {
        let day = testDate(day: 1)
        let repository = try DiaryRepository(fileURL: temporaryDiaryURL(), calendar: testCalendar, catalog: resolutionCatalog)
        let bacon = MealItem(id: UUID(), food: testFood(calories: 32, name: "Bacon"), amount: 1, unit: .serving)
        let beans = MealItem(id: UUID(), food: testFood(calories: 73, name: "White beans"), amount: 1, unit: .serving)
        let meal = SavedMeal(id: UUID(), name: "Soup", items: [beans])
        try repository.performSync(scope: .day(day)) { $0.logOneOffMeal(meal, on: day) }
        let id = try XCTUnwrap(repository.snapshotSync().document.entries.first?.id)
        try repository.performSync(scope: .entries([id])) { $0.updateMealEntry(entryID: id, amount: 1, items: [bacon, beans]) }
        var document = try repository.snapshotSync().document
        XCTAssertTrue(DiaryEngine(document: document, calendar: testCalendar).meatPresence(on: day).containsProcessedMeat)
        try repository.performSync(scope: .entries([id])) { $0.updateMealEntry(entryID: id, amount: 1, items: [beans]) }
        document = try repository.snapshotSync().document
        XCTAssertFalse(DiaryEngine(document: document, calendar: testCalendar).meatPresence(on: day).containsProcessedMeat)
        let overridden = SavedMeal(id: UUID(), name: "Explicit no", items: [bacon], containsProcessedMeat: false)
        try repository.performSync(scope: .day(day)) { $0.logOneOffMeal(overridden, on: day) }
        let overrideID = try XCTUnwrap(repository.snapshotSync().document.entries.last?.id)
        try repository.performSync(scope: .entries([overrideID])) {
            $0.updateMealEntry(entryID: overrideID, amount: 1, items: [bacon, beans])
        }
        document = try repository.snapshotSync().document
        XCTAssertFalse(DiaryEngine(document: document, calendar: testCalendar).meatPresence(on: day).containsProcessedMeat)
    }

    func testHistoricalResolutionRequiresReviewPreservesDataAndRejectsStaleSuggestions() throws {
        let day = testDate(day: 1)
        let url = temporaryDiaryURL()
        let repository = try DiaryRepository(fileURL: url, calendar: testCalendar, catalog: resolutionCatalog)
        var bacon = testFood(calories: 32, name: "Bacon")
        bacon.containsProcessedMeat = false
        bacon.containsRedMeat = false
        var initial = DiaryDocument()
        initial.customFoods = [bacon]
        initial.favorites = [bacon]
        initial.rememberedQuantities[bacon.id] = QuantityPreference(amount: 2, unit: .serving)
        let ingredient = MealItem(id: UUID(), food: bacon, amount: 1, unit: .serving)
        initial.meals = [SavedMeal(id: UUID(), name: "Soup", items: [ingredient], origin: .imported)]
        try repository.importDocument(initial)
        try repository.performSync(scope: .day(day)) { $0.logMeal(initial.meals[0], on: day) }
        let before = try repository.snapshotSync().document
        let review = try XCTUnwrap(DiaryEngine(document: before, catalog: resolutionCatalog).foodResolutionReview().first)
        XCTAssertFalse(DiaryEngine(document: before, calendar: testCalendar).meatPresence(on: day).containsProcessedMeat)
        let backup = url.deletingLastPathComponent().appendingPathComponent("BeforeCorrection.sqlite")
        try repository.backup(to: backup)
        try repository.performSync(scope: .food(bacon.id)) { try $0.applyFoodResolutionReview(review) }
        let after = try repository.snapshotSync().document
        XCTAssertEqual(after.entries[0].nutrients, before.entries[0].nutrients)
        XCTAssertEqual(after.entries[0].id, before.entries[0].id)
        XCTAssertEqual(after.entries[0].mealItems?[0].id, ingredient.id)
        XCTAssertEqual(after.rememberedQuantities, before.rememberedQuantities)
        XCTAssertEqual(after.customFoods[0].containsProcessedMeat, true)
        XCTAssertEqual(after.favorites[0].meatResolution?.processed, .user)
        XCTAssertEqual(after.meals[0].items[0].food.containsProcessedMeat, true)
        XCTAssertTrue(DiaryEngine(document: after, calendar: testCalendar).meatPresence(on: day).containsProcessedMeat)
        let second = try DiaryRepository(fileURL: url, calendar: testCalendar)
        XCTAssertThrowsError(try second.performSync(scope: .food(bacon.id)) { try $0.applyFoodResolutionReview(review) })
        XCTAssertEqual(try DiaryJSONMigration.canonicalData(after), try DiaryJSONMigration.canonicalData(repository.snapshotSync().document))
        let restored = try DiaryRepository(fileURL: backup, calendar: testCalendar)
        XCTAssertEqual(try DiaryJSONMigration.canonicalData(before), try DiaryJSONMigration.canonicalData(restored.snapshotSync().document))
    }

    @MainActor
    func testApproveAllClassificationsCreatesOneBackupAndPreservesMealOverrides() async throws {
        let url = temporaryDiaryURL()
        let oldDay = testCalendar.date(byAdding: .year, value: -3, to: testDate(day: 1))!
        var bacon = testFood(calories: 32, name: "Bacon")
        bacon.containsProcessedMeat = false
        bacon.containsRedMeat = false
        var beef = testFood(calories: 120, name: "Beef")
        beef.containsProcessedMeat = false
        beef.containsRedMeat = false
        let meal = SavedMeal(id: UUID(), name: "Reviewed soup", items: [
            MealItem(id: UUID(), food: bacon, amount: 2, unit: .serving),
            MealItem(id: UUID(), food: beef, amount: 1, unit: .serving)
        ], containsProcessedMeat: false)
        var original = DiaryDocument()
        original.customFoods = [bacon, beef]
        original.favorites = [bacon]
        original.meals = [meal]
        let engine = DiaryEngine(document: original, calendar: testCalendar)
        engine.logMeal(meal, on: oldDay)
        engine.log(bacon, amount: 3, unit: .serving, on: oldDay)
        engine.log(testFood(calories: 55, name: "House special"), amount: 1, unit: .serving, on: oldDay)
        let store = DiaryStore(document: engine.document, fileURL: url, calendar: testCalendar,
                               catalog: resolutionCatalog, usesWindow: false)
        await store.reloadFromDisk(referenceDate: oldDay)
        let before = try XCTUnwrap(store.repository).snapshotSync().document
        let reviews = try await store.foodResolutionReview()
        XCTAssertEqual(reviews.count, 2)
        try await store.applyFoodResolutionReviews(reviews)
        let reopened = try DiaryRepository(fileURL: url, calendar: testCalendar)
        let after = try reopened.snapshotSync().document
        XCTAssertEqual(after.customFoods.map(\.containsProcessedMeat), [true, false])
        XCTAssertEqual(after.customFoods.map(\.containsRedMeat), [false, true])
        XCTAssertEqual(after.favorites[0].containsProcessedMeat, true)
        XCTAssertEqual(after.entries.map(\.id), before.entries.map(\.id))
        XCTAssertEqual(after.entries.map(\.nutrients), before.entries.map(\.nutrients))
        XCTAssertEqual(after.entries.map(\.amount), before.entries.map(\.amount))
        XCTAssertEqual(after.rememberedQuantities, before.rememberedQuantities)
        let updatedMeal = try XCTUnwrap(after.entries.first { $0.isMeal })
        XCTAssertEqual(updatedMeal.mealItems?.map(\.food.containsProcessedMeat), [true, false])
        XCTAssertEqual(updatedMeal.mealItems?.map(\.food.containsRedMeat), [false, true])
        XCTAssertEqual(updatedMeal.processedMeatOverride, false)
        XCTAssertEqual(updatedMeal.food.containsProcessedMeat, false)
        XCTAssertEqual(updatedMeal.food.containsRedMeat, true)
        XCTAssertEqual(after.entries.last, before.entries.last, "Unmatched snapshots must not change.")
        let remaining = try await store.foodResolutionReview()
        XCTAssertTrue(remaining.isEmpty)
        let backupDirectory = url.deletingLastPathComponent().appendingPathComponent("ClassificationBackups")
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sqlite" }
        XCTAssertEqual(backups.count, 1, "One consistent backup for the whole batch, not one per suggestion.")
        let backup = try DiaryRepository(fileURL: XCTUnwrap(backups.first), calendar: testCalendar)
        try backup.validate()
        XCTAssertEqual(try DiaryJSONMigration.canonicalData(before),
                       try DiaryJSONMigration.canonicalData(backup.snapshotSync().document))
        try reopened.validate()
    }

    func testApproveAllClassificationsRejectsStaleAndDuplicateBatchesWithoutPartialChanges() throws {
        let url = temporaryDiaryURL()
        let repository = try DiaryRepository(fileURL: url, calendar: testCalendar, catalog: resolutionCatalog)
        var original = DiaryDocument()
        original.customFoods = ["Bacon", "Beef"].map { name in
            var food = testFood(calories: 32, name: name)
            food.containsProcessedMeat = false
            food.containsRedMeat = false
            return food
        }
        try repository.importDocument(original)
        let reviews = DiaryEngine(document: original, catalog: resolutionCatalog).foodResolutionReview()
        XCTAssertEqual(reviews.count, 2)
        let duplicateEngine = DiaryEngine(document: original, catalog: resolutionCatalog)
        XCTAssertThrowsError(try duplicateEngine.applyFoodResolutionReviews([reviews[0], reviews[0]]))
        XCTAssertEqual(duplicateEngine.document.customFoods, original.customFoods)
        let otherWriter = try DiaryRepository(fileURL: url, calendar: testCalendar, catalog: resolutionCatalog)
        try otherWriter.performSync(scope: .food(original.customFoods[1].id)) {
            $0.document.customFoods[1].name = "Changed while reviewing"
        }
        let before = try repository.snapshotSync()
        XCTAssertThrowsError(try repository.performSync(scope: .foods(Set(reviews.map { $0.food.id }))) {
            try $0.applyFoodResolutionReviews(reviews)
        })
        let after = try repository.snapshotSync()
        XCTAssertEqual(after.revision, before.revision)
        XCTAssertEqual(try DiaryJSONMigration.canonicalData(after.document),
                       try DiaryJSONMigration.canonicalData(before.document))
        let inMemory = DiaryEngine(document: before.document, catalog: resolutionCatalog)
        XCTAssertThrowsError(try inMemory.applyFoodResolutionReviews(reviews))
        XCTAssertEqual(inMemory.document.customFoods, before.document.customFoods)
    }

    @MainActor
    func testApproveAllClassificationsRequiresBackupAndEmptyBatchIsANoOp() async throws {
        let url = temporaryDiaryURL()
        var bacon = testFood(calories: 32, name: "Bacon")
        bacon.containsProcessedMeat = false
        bacon.containsRedMeat = false
        var initial = DiaryDocument()
        initial.customFoods = [bacon]
        let store = DiaryStore(document: initial, fileURL: url, catalog: resolutionCatalog)
        await store.reloadFromDisk()
        let repository = try XCTUnwrap(store.repository)
        let before = try repository.snapshotSync()
        let directory = url.deletingLastPathComponent().appendingPathComponent("ClassificationBackups")
        try await store.applyFoodResolutionReviews([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        // A file at the backup-directory path forces a real filesystem failure.
        try Data("not a directory".utf8).write(to: directory)
        let reviews = try await store.foodResolutionReview()
        do {
            try await store.applyFoodResolutionReviews(reviews)
            XCTFail("Classification changes require a successful backup.")
        } catch { }
        let after = try repository.snapshotSync()
        XCTAssertEqual(after.revision, before.revision)
        XCTAssertEqual(try DiaryJSONMigration.canonicalData(after.document),
                       try DiaryJSONMigration.canonicalData(before.document))
    }

    func testBatchFoodScopeHandlesManyIDsAndIncludesHistoricalIngredients() throws {
        let day = testDate(day: 1)
        let repository = try DiaryRepository(fileURL: temporaryDiaryURL(), catalog: resolutionCatalog)
        let bacon = testFood(calories: 32, name: "Bacon")
        let meal = SavedMeal(id: UUID(), name: "Soup", items: [
            MealItem(id: UUID(), food: bacon, amount: 1, unit: .serving)
        ])
        try repository.performSync(scope: .day(day)) {
            $0.logOneOffMeal(meal, on: day)
            $0.log(testFood(calories: 55, name: "House special"), amount: 1, unit: .serving, on: day)
        }
        var ids = Set((0..<1_500).map { "missing:\($0)" })
        ids.insert(bacon.id)
        ids.insert("food:'quoted\"id")
        let snapshot = try repository.snapshotSync(scope: .foods(ids)).document
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries[0].mealItems?.first?.food.id, bacon.id)
        XCTAssertTrue(try repository.snapshotSync(scope: .foods([])).document.entries.isEmpty)
    }

    func testKnownBaconSandwichCatalogFlagsAndNameRulesAgree() {
        for id in ["170312", "170313"] {
            XCTAssertEqual(resolutionCatalog.food(sourceID: id, source: .usda)?.containsProcessedMeat, true)
        }
        XCTAssertTrue(DiaryEngine.fallbackMeatClassification(for: "Bacon sandwich on white bread").containsProcessedMeat)
        XCTAssertFalse(DiaryEngine.fallbackMeatClassification(for: "Hot dog buns").containsProcessedMeat)
    }

    func testUnknownMeatCountsAndStaleMealLoggingUseCommittedClassification() throws {
        let day = testDate(day: 1)
        let repository = try DiaryRepository(fileURL: temporaryDiaryURL(), calendar: testCalendar, catalog: resolutionCatalog)
        let unknown = testFood(calories: 200, name: "House special")
        let bacon = testFood(calories: 32, name: "Bacon")
        let stale = SavedMeal(id: UUID(), name: "Soup", items: [MealItem(id: UUID(), food: unknown, amount: 1, unit: .serving)])
        try repository.performSync(scope: .day(day)) { engine in
            engine.document.meals = [stale]
            engine.logMeal(stale, on: day)
        }
        var engine = DiaryEngine(document: try repository.snapshotSync().document, calendar: testCalendar)
        XCTAssertEqual(engine.unknownMeatEntryCount(numberOfDays: 1, referenceDate: day), 1)
        try repository.performSync(scope: .meal(stale.id)) {
            _ = $0.updateSavedMeal(mealID: stale.id, name: stale.name,
                items: [MealItem(id: UUID(), food: bacon, amount: 1, unit: .serving)])
        }
        try repository.performSync(scope: .day(day)) { $0.logMeal(stale, on: day) }
        engine = DiaryEngine(document: try repository.snapshotSync().document, calendar: testCalendar)
        XCTAssertEqual(engine.unknownMeatEntryCount(numberOfDays: 1, referenceDate: day), 0)
        XCTAssertEqual(engine.weeklyMeatDays(numberOfDays: 1, referenceDate: day).first?.processedMeatDays, 1)
        let mixed = FoodResolver(catalog: nil).resolve(testFood(calories: 200, name: "Bacon soup"))
        XCTAssertEqual(mixed.containsProcessedMeat, true)
        XCTAssertNil(mixed.containsRedMeat, "Naming bacon is not evidence that a soup has no other meat.")
    }

    func testOnDeviceJSONMigrationPreservesBackupAndIsIdempotent() throws {
        let destination = temporaryDiaryURL()
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = directory.appendingPathComponent("Shared.json")
        let old = directory.appendingPathComponent("Old.json")
        let backups = directory.appendingPathComponent("Backups")
        var document = DiaryDocument()
        document.dailyCalorieGoal = 2100
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(document)
        try bytes.write(to: shared)
        try encoder.encode(DiaryDocument()).write(to: old)
        let backup = try XCTUnwrap(DiaryJSONMigration.convertIfNeeded(
            destination: destination, sources: [shared, old], backupDirectory: backups))
        XCTAssertEqual(try Data(contentsOf: shared), bytes)
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertEqual(try DiaryRepository(fileURL: destination).snapshotSync().document.dailyCalorieGoal, 2100)
        XCTAssertNil(try DiaryJSONMigration.convertIfNeeded(
            destination: destination, sources: [shared], backupDirectory: backups))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 1)
    }

    func testOnDeviceJSONMigrationRefusesCorruptSourceWithoutUsingStaleFallback() throws {
        let destination = temporaryDiaryURL()
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Shared.json")
        let fallback = directory.appendingPathComponent("Old.json")
        let backups = directory.appendingPathComponent("Backups")
        let bytes = Data("damaged current diary".utf8)
        try bytes.write(to: source)
        try Data("{\"schemaVersion\":8,\"entries\":[]}".utf8).write(to: fallback)
        XCTAssertThrowsError(try DiaryJSONMigration.convertIfNeeded(
            destination: destination, sources: [source, fallback], backupDirectory: backups))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Diary.json")), bytes)
    }

    func testSQLStreakMatchesDomainAfterTimeZoneChange() async throws {
        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let reference = try XCTUnwrap(origin.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)))
        let food = Food(sourceID: "timezone", source: .custom, name: "Food", brand: nil, barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 2, protein: 5), baseAmountGrams: 100,
            servingGrams: 100, servingDescription: "serving")
        var document = DiaryDocument()
        document.entries = [-1, 0].map { offset in
            let day = origin.startOfDay(for: origin.date(byAdding: .day, value: offset, to: reference)!)
            return DiaryEntry(id: UUID(), date: day, food: food, amount: 1, unit: .serving,
                nutrients: food.nutrients, loggedAt: day)
        }
        document.trackingStartDate = document.entries.first?.date
        var knownFiberFood = food
        knownFiberFood.nutrients.fiber = 4
        document.entries[0].mealItems = [
            MealItem(id: UUID(), food: knownFiberFood, amount: 0.5, unit: .serving),
            MealItem(id: UUID(), food: food, amount: 0.5, unit: .serving)
        ]
        let repository = try DiaryRepository(fileURL: temporaryDiaryURL(), calendar: destination)
        try repository.importDocument(document)
        let actual = try await repository.streak(referenceDate: reference)
        let expected = DiaryEngine(document: document, calendar: destination).streak(referenceDate: reference)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.dayCount, 2)
        XCTAssertEqual(actual.averageNutrients.fiber, 1)
        document.trackingStartDate = destination.startOfDay(for: reference)
        let trackingStart = document.trackingStartDate
        try repository.performSync(scope: .library) { $0.document.trackingStartDate = trackingStart }
        let limited = try await repository.streak(referenceDate: reference)
        XCTAssertEqual(limited, DiaryEngine(document: document, calendar: destination).streak(referenceDate: reference))
        XCTAssertEqual(limited.dayCount, 1)
    }

    @MainActor
    func testAsyncDiaryStoreCommitsAndLoadsAnOlderSelectedDay() async throws {
        let url = temporaryDiaryURL()
        let today = Calendar.current.startOfDay(for: Date())
        let oldDay = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -3, to: today))
        let food = Food(sourceID: "old-async", source: .custom, name: "Historic food", brand: nil,
                        barcode: nil, nutrients: .zero, baseAmountGrams: 100, servingGrams: 100,
                        servingDescription: "serving")
        let store = DiaryStore(fileURL: url)
        XCTAssertTrue(store.isLoading)
        XCTAssertFalse(store.hasLoadedSnapshot)
        await store.reloadFromDisk()
        XCTAssertNil(store.lastSaveError)
        try await store.log(food, amount: 1, unit: .serving, on: oldDay)
        await store.selectDay(oldDay)
        XCTAssertEqual(store.entries(on: oldDay).count, 1)
        let reloaded = try DiaryRepository(fileURL: url).snapshotSync().document
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertTrue(store.hasLoadedSnapshot)
    }

    @MainActor
    func testFailedDiaryLoadDoesNotPublishAnEmptyUsableStore() async throws {
        let url = temporaryDiaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("corrupt source must remain intact".utf8)
        try original.write(to: url)
        let store = DiaryStore(fileURL: url)
        await store.reloadFromDisk()
        XCTAssertNotNil(store.lastSaveError)
        XCTAssertFalse(store.hasLoadedSnapshot)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testWidgetLogFoodDeepLinkRoutesOnlyTheExpectedURL() throws {
        XCTAssertEqual(
            VitaChaseDeepLink(url: VitaChaseDeepLink.logFoodURL),
            .logFood
        )
        XCTAssertNil(VitaChaseDeepLink(url: try XCTUnwrap(URL(string: "vitachase://settings"))))
        XCTAssertNil(VitaChaseDeepLink(url: try XCTUnwrap(URL(string: "https://example.com/log-food"))))
    }

    func testFirstTimeOnboardingAppearsForAnEmptyDiary() {
        let suiteName = "CalorieTrackerTests.Onboarding.Empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FirstTimeOnboarding.prepareForLaunch(
            document: DiaryDocument(),
            defaults: defaults
        )

        XCTAssertNil(defaults.object(forKey: FirstTimeOnboarding.completedKey))
        XCTAssertFalse(defaults.bool(forKey: FirstTimeOnboarding.completedKey))
    }

    func testFirstTimeOnboardingSkipsExistingUsers() {
        let suiteName = "CalorieTrackerTests.Onboarding.Existing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var document = DiaryDocument()
        document.dailyCalorieGoal = 2_000

        FirstTimeOnboarding.prepareForLaunch(
            document: document,
            defaults: defaults
        )

        XCTAssertTrue(defaults.bool(forKey: FirstTimeOnboarding.completedKey))
    }

    func testFirstTimeOnboardingPreservesAnExplicitDeveloperReset() {
        let suiteName = "CalorieTrackerTests.Onboarding.Reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: FirstTimeOnboarding.completedKey)
        var document = DiaryDocument()
        document.dailyCalorieGoal = 2_000

        FirstTimeOnboarding.prepareForLaunch(
            document: document,
            defaults: defaults
        )

        XCTAssertFalse(defaults.bool(forKey: FirstTimeOnboarding.completedKey))
    }

    func testOlderNutrientSnapshotsDecodeFiberAsUnavailable() throws {
        let data = Data(#"{"calories":100,"carbs":20,"fat":2,"protein":5}"#.utf8)

        let nutrients = try JSONDecoder().decode(MacroNutrients.self, from: data)

        XCTAssertNil(nutrients.fiber)
    }

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
        let store = TestDiaryStore(
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
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))

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
        let unloggedStore = TestDiaryStore(
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
        let loggedStore = TestDiaryStore(
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
        let store = TestDiaryStore(
            document: document,
            fileURL: folder.appendingPathComponent("diary.json"),
            calendar: calendar,
            referenceDate: date(8, 8)
        )

        let excludedResult = store.magicSuggestionResult(at: date(8, 8))
        XCTAssertTrue(excludedResult.suggestions.isEmpty)
        XCTAssertTrue(excludedResult.hasExcludedMatches)

        let emptyStore = TestDiaryStore(
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
        let store = TestDiaryStore(
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

    func testRichSimulatorFixtureCoversThirtyDaysAndLibraryData() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 20,
            hour: 5
        ))!
        let document = DiaryFixtureLoader.makeRichDemoDocument(
            DiaryDocument(),
            referenceDate: referenceDate,
            calendar: calendar
        )
        let trackedDays = Set(document.entries.compactMap { entry -> Date? in
            let day = calendar.startOfDay(for: entry.date)
            let offset = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: referenceDate),
                to: day
            ).day ?? 1
            return (-29 ... 0).contains(offset) ? day : nil
        })
        let engine = DiaryEngine(document: document, calendar: calendar)
        let meatDays = (-29 ... 0).compactMap {
            calendar.date(byAdding: .day, value: $0, to: referenceDate)
        }.map { engine.meatPresence(on: $0) }

        XCTAssertEqual(trackedDays.count, 30)
        XCTAssertEqual(document.alcoholEntries.count, 9)
        XCTAssertEqual(document.customFoods.count, 15)
        XCTAssertEqual(document.meals.count, 5)
        XCTAssertEqual(document.meals.filter(\.isImported).count, 3)
        XCTAssertFalse(document.dayStatuses.contains { $0.kind == .gap })
        XCTAssertTrue(meatDays.contains { $0.containsProcessedMeat })
        XCTAssertTrue(meatDays.contains { $0.containsRedMeat })
        XCTAssertGreaterThan(engine.totals(on: referenceDate).calories, 2_000)
        XCTAssertGreaterThan(engine.totals(on: referenceDate).fiber ?? 0, 0)
        XCTAssertNoThrow(try DiaryRepository.validateDocument(document))
    }

    @MainActor
    func testDailyCalorieGoalPersistsAndCanBeRemoved() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let store = TestDiaryStore(fileURL: fileURL)

        XCTAssertNil(store.dailyCalorieGoal)
        store.setDailyCalorieGoal(2_200)
        XCTAssertEqual(store.dailyCalorieGoal, 2_200)
        XCTAssertEqual(TestDiaryStore(fileURL: fileURL).dailyCalorieGoal, 2_200)

        store.setDailyCalorieGoal(0)
        XCTAssertNil(store.dailyCalorieGoal)
        XCTAssertNil(TestDiaryStore(fileURL: fileURL).dailyCalorieGoal)
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
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let food = Food(
            sourceID: "banana",
            source: .usda,
            name: "Banana",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(
                calories: 89,
                carbs: 22.8,
                fat: 0.3,
                protein: 1.1,
                fiber: 2.6
            ),
            baseAmountGrams: 100,
            servingGrams: 118,
            servingDescription: "1 medium"
        )

        store.log(food, amount: 50, unit: .grams, on: Date())

        let entry = try XCTUnwrap(store.entries(on: Date()).first)
        XCTAssertEqual(entry.nutrients.calories, 44.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(entry.nutrients.fiber), 1.3, accuracy: 0.001)
        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 50, unit: .grams))
    }

    @MainActor
    func testFiberDailyTotalUsesKnownEntriesWhenOtherFoodsLackFiberData() throws {
        let day = testDate(day: 1)
        let store = TestDiaryStore(
            document: DiaryDocument(),
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: day
        )
        var knownFiberFood = testFood(calories: 100, name: "Beans")
        knownFiberFood.nutrients.fiber = 7
        store.log(knownFiberFood, amount: 1, unit: .serving, on: day)
        XCTAssertEqual(try XCTUnwrap(store.totals(on: day).fiber), 7, accuracy: 0.001)

        store.log(testFood(calories: 50, name: "Unknown fiber food"), amount: 1, unit: .serving, on: day)

        XCTAssertEqual(try XCTUnwrap(store.totals(on: day).fiber), 7, accuracy: 0.001)
    }

    @MainActor
    func testFiberDailyTotalUsesKnownMealComponentsWhenMealFiberIsIncomplete() throws {
        let day = testDate(day: 1)
        let store = TestDiaryStore(
            document: DiaryDocument(),
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: day
        )
        var knownFiberFood = testFood(calories: 100, name: "Lentils")
        knownFiberFood.nutrients.fiber = 8
        let unknownFiberFood = testFood(calories: 50, name: "Unknown meal ingredient")
        let meal = try XCTUnwrap(store.saveMeal(name: "Mixed meal", items: [
            MealItem(id: UUID(), food: knownFiberFood, amount: 1, unit: .serving, portionID: "serving"),
            MealItem(id: UUID(), food: unknownFiberFood, amount: 1, unit: .serving, portionID: "serving")
        ]))

        store.logMeal(meal, on: day)

        XCTAssertNil(store.entries(on: day).first?.nutrients.fiber)
        XCTAssertEqual(try XCTUnwrap(store.totals(on: day).fiber), 8, accuracy: 0.001)
    }

    @MainActor
    func testDeletingMultipleEntriesRemovesOnlySelectedItemsAndPersists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = TestDiaryStore(fileURL: fileURL)

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
        XCTAssertEqual(TestDiaryStore(fileURL: fileURL).entries(on: day).map(\.food.name), ["Eggs"])
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
        let store = TestDiaryStore(fileURL: fileURL)
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

        let reloaded = TestDiaryStore(fileURL: fileURL)
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
        let store = TestDiaryStore(fileURL: fileURL)

        store.log(food, amount: 100, unit: .grams, on: day)
        store.toggleFavorite(food)

        XCTAssertTrue(store.renameFood(foodID: food.id, name: "My chicken"))
        XCTAssertEqual(store.entries(on: day).first?.food.name, "My chicken")
        XCTAssertEqual(store.document.favorites.first?.name, "My chicken")
        XCTAssertEqual(store.displayedFood(food).name, "My chicken")
        XCTAssertEqual(store.searchPersonalFoods("my chicken").first?.name, "My chicken")

        let reloaded = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).first?.food.name, "My chicken")
        XCTAssertEqual(reloaded.searchPersonalFoods("chicken").first?.name, "My chicken")
    }

    @MainActor
    func testRenamingLoggedFoodPublishesAnImmediateChange() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
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
        let store = TestDiaryStore(fileURL: fileURL)

        store.toggleFavorite(egg, preference: preference)

        let reloaded = TestDiaryStore(fileURL: fileURL)
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
        let store = TestDiaryStore(fileURL: fileURL)

        store.saveMeal(
            name: "Zebra meal",
            items: [MealItem(id: UUID(), food: food, amount: 100, unit: .grams)]
        )
        let meal = try XCTUnwrap(store.document.meals.first)
        store.toggleFavorite(food)
        store.toggleFavorite(meal)

        let reloaded = TestDiaryStore(fileURL: fileURL)
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
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))

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
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
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
        let store = TestDiaryStore(fileURL: fileURL)

        let food = store.addCustomFood(
            name: "Original oats",
            brand: "Kitchen",
            calories: 100,
            carbs: 20,
            fat: 2,
            protein: 4,
            fiber: 3,
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
            fiber: 5,
            servingGrams: 50
        ))

        XCTAssertEqual(store.document.customFoods.first?.name, "Updated oats")
        XCTAssertEqual(store.document.customFoods.first?.nutrients.calories, 150)
        XCTAssertEqual(store.document.customFoods.first?.nutrients.fiber, 5)
        XCTAssertEqual(store.document.meals.first?.items.first?.food.name, "Updated oats")
        XCTAssertEqual(store.document.meals.first?.nutrients.fiber, 5)
        let loggedFood = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertEqual(loggedFood.food.name, "Updated oats")
        XCTAssertEqual(loggedFood.nutrients.calories, 150, accuracy: 0.001)
        XCTAssertEqual(loggedFood.nutrients.fiber, 5)

        let reloaded = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.customFoods.first?.name, "Updated oats")
        XCTAssertEqual(reloaded.document.meals.first?.items.first?.food.name, "Updated oats")
    }

    @MainActor
    func testSavedMealCanBeEditedAndUpdatesLoggedMealEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = TestDiaryStore(fileURL: fileURL)

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

        let reloaded = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.meals.first?.name, "New breakfast")
        let reloadedMeal = try XCTUnwrap(reloaded.entries(on: day).first)
        XCTAssertEqual(reloadedMeal.nutrients.calories, 560, accuracy: 0.001)
    }

    @MainActor
    func testReorderedDiaryEntriesPersistAndNewEntriesStayAtTop() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = TestDiaryStore(fileURL: fileURL)

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
        let reloaded = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["B", "A", "C"])

        reloaded.log(food("D"), amount: 100, unit: .grams, on: day)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["D", "B", "A", "C"])
    }

    @MainActor
    func testRepeatedMovesUpdateOrderAsAnEntryCrossesEachRow() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
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
        let store = TestDiaryStore(fileURL: fileURL)

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

        let reloaded = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Coffee", "Breakfast"])
        XCTAssertEqual(reloaded.totals(on: day), totalsBefore)

        let mealEntryID = try XCTUnwrap(reloaded.entries(on: day).last?.id)
        reloaded.breakApartMeal(entryID: mealEntryID)

        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Coffee", "Eggs", "Toast"])
        XCTAssertTrue(reloaded.entries(on: day).allSatisfy { !$0.isMeal })
        XCTAssertEqual(reloaded.totals(on: day), totalsBefore)
        XCTAssertEqual(reloaded.document.meals.count, 1)

        let expandedReload = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(expandedReload.entries(on: day).map(\.food.name), ["Coffee", "Eggs", "Toast"])
        XCTAssertEqual(expandedReload.totals(on: day), totalsBefore)
    }

    @MainActor
    func testLoggingSavedMealCreatesOneBreakableDiaryEntry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = TestDiaryStore(fileURL: fileURL)

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

        let reloaded = TestDiaryStore(fileURL: fileURL)
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

        let banana = try XCTUnwrap(
            catalog.search("banana raw", source: .usda).first { $0.name == "Banana, raw" }
        )
        XCTAssertEqual(try XCTUnwrap(banana.nutrients.fiber), 1.7, accuracy: 0.001)
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

    func testCatalogClassifiesProcessedAndRedMeatPresence() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = CatalogStore(url: projectRoot.appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))

        XCTAssertEqual(
            catalog.meatClassification(sourceID: "2705889", source: .usda),
            MeatClassification(containsProcessedMeat: true, containsRedMeat: false)
        )
        XCTAssertEqual(
            catalog.meatClassification(sourceID: "168652", source: .usda),
            MeatClassification(containsProcessedMeat: false, containsRedMeat: true)
        )
        XCTAssertEqual(
            catalog.meatClassification(sourceID: "2707465", source: .usda),
            MeatClassification.none
        )
        XCTAssertEqual(
            catalog.meatClassification(sourceID: "2706980", source: .usda),
            MeatClassification(containsProcessedMeat: true, containsRedMeat: false)
        )
    }

    @MainActor
    func testExistingDiaryFoodsBackfillMeatFlagsFromCatalogAndNames() {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = CatalogStore(url: projectRoot.appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))
        let day = testDate(day: 1)
        var bacon = testFood(calories: 100, name: "Legacy bacon")
        bacon = Food(
            sourceID: "2705889",
            source: .usda,
            name: bacon.name,
            brand: bacon.brand,
            barcode: bacon.barcode,
            nutrients: bacon.nutrients,
            baseAmountGrams: bacon.baseAmountGrams,
            servingGrams: bacon.servingGrams,
            servingDescription: bacon.servingDescription,
            portions: bacon.portions
        )
        let customPepperoni = testFood(calories: 80, name: "House pepperoni")
        var document = DiaryDocument()
        document.entries = [
            DiaryEntry(
                id: UUID(),
                date: day,
                food: bacon,
                amount: 1,
                unit: .serving,
                nutrients: bacon.nutrients,
                loggedAt: day
            )
        ]
        document.customFoods = [customPepperoni]

        let store = TestDiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            catalog: catalog,
            referenceDate: day
        )

        XCTAssertEqual(store.entries(on: day).first?.food.containsProcessedMeat, true)
        XCTAssertEqual(store.entries(on: day).first?.food.containsRedMeat, false)
        XCTAssertEqual(store.entries(on: day).first?.nutrients.fiber, 0)
        XCTAssertEqual(store.document.customFoods.first?.containsProcessedMeat, true)
        XCTAssertEqual(store.document.customFoods.first?.containsRedMeat, false)
    }

    @MainActor
    func testWeeklyMeatTrendsCountEachCategoryAtMostOncePerDay() {
        let firstDay = testDate(day: 1)
        let secondDay = testDate(day: 2)
        let fifthDay = testDate(day: 5)
        let referenceDay = testDate(day: 8)
        let store = TestDiaryStore(
            document: DiaryDocument(),
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: referenceDay
        )
        var processed = testFood(calories: 100, name: "Processed test food")
        processed.containsProcessedMeat = true
        processed.containsRedMeat = false
        var red = testFood(calories: 100, name: "Red test food")
        red.containsProcessedMeat = false
        red.containsRedMeat = true
        var mixed = testFood(calories: 100, name: "Mixed test food")
        mixed.containsProcessedMeat = true
        mixed.containsRedMeat = true

        store.log(processed, amount: 1, unit: .serving, on: firstDay)
        store.log(processed, amount: 1, unit: .serving, on: firstDay)
        store.log(red, amount: 1, unit: .serving, on: secondDay)
        store.log(mixed, amount: 1, unit: .serving, on: fifthDay)

        let weeks = store.weeklyMeatDays(numberOfDays: 8, referenceDate: referenceDay)
        XCTAssertEqual(weeks.map(\.processedMeatDays).reduce(0, +), 2)
        XCTAssertEqual(weeks.map(\.redMeatDays).reduce(0, +), 2)
        XCTAssertEqual(store.meatPresence(on: firstDay).containsProcessedMeat, true)
        XCTAssertEqual(store.meatPresence(on: firstDay).containsRedMeat, false)
    }

    @MainActor
    func testMeatDayDetailsListQualifyingFoodsAndExpandMeals() throws {
        let day = testDate(day: 1)
        let store = TestDiaryStore(
            document: DiaryDocument(),
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: day
        )
        var bacon = testFood(calories: 100, name: "Bacon")
        bacon.containsProcessedMeat = true
        bacon.containsRedMeat = false
        var steak = testFood(calories: 200, name: "Steak")
        steak.containsProcessedMeat = false
        steak.containsRedMeat = true

        store.log(bacon, amount: 1, unit: .serving, on: day)
        store.log(bacon, amount: 1, unit: .serving, on: day)
        let meal = try XCTUnwrap(store.saveMeal(
            name: "Steak dinner",
            items: [MealItem(id: UUID(), food: steak, amount: 1, unit: .serving)]
        ))
        store.logMeal(meal, on: day)

        let details = try XCTUnwrap(
            store.meatDayFoods(numberOfDays: 1, referenceDate: day).first
        )
        XCTAssertEqual(details.processedMeatFoods, ["Bacon"])
        XCTAssertEqual(details.redMeatFoods, ["Steak dinner — Steak"])
    }

    @MainActor
    func testCustomFoodAndMealMeatFlagsAreEditableOverrides() throws {
        let store = TestDiaryStore(fileURL: temporaryDiaryURL())
        let food = store.addCustomFood(
            name: "House plate",
            brand: "",
            calories: 200,
            carbs: 5,
            fat: 10,
            protein: 20,
            servingGrams: 100,
            containsProcessedMeat: true,
            containsRedMeat: false
        )
        XCTAssertEqual(food.containsProcessedMeat, true)
        XCTAssertTrue(store.updateCustomFood(
            foodID: food.id,
            name: food.name,
            brand: "",
            calories: 200,
            carbs: 5,
            fat: 10,
            protein: 20,
            servingGrams: 100,
            containsProcessedMeat: false,
            containsRedMeat: true
        ))
        let updatedFood = try XCTUnwrap(store.document.customFoods.first)
        let meal = try XCTUnwrap(store.saveMeal(
            name: "Override meal",
            items: [MealItem(id: UUID(), food: updatedFood, amount: 1, unit: .serving)],
            containsProcessedMeat: true,
            containsRedMeat: false
        ))
        XCTAssertTrue(meal.resolvedContainsProcessedMeat)
        XCTAssertFalse(meal.resolvedContainsRedMeat)
    }

    @MainActor
    func testNewFoodsUseLastSelectedWeightUnitAndStartWithOunces() {
        let previous = UserDefaults.standard.object(forKey: "lastWeightUnit")
        let shared = UserDefaults(suiteName: SharedDiaryStorage.appGroupIdentifier)!
        let previousShared = shared.object(forKey: "lastWeightUnit")
        shared.removeObject(forKey: "lastWeightUnit")
        defer {
            if let previousShared { shared.set(previousShared, forKey: "lastWeightUnit") }
            else { shared.removeObject(forKey: "lastWeightUnit") }
            if let previous {
                UserDefaults.standard.set(previous, forKey: "lastWeightUnit")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastWeightUnit")
            }
        }
        UserDefaults.standard.removeObject(forKey: "lastWeightUnit")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
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

        store.rememberLastWeightUnit(.grams)
        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 100, unit: .grams))

        store.rememberLastWeightUnit(.serving)
        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 100, unit: .grams))
    }

    @MainActor
    func testQuickLogUsesDisplayedPreferenceAndFavoritesRemainAvailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
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
        let store = TestDiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
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
        let store = TestDiaryStore(fileURL: fileURL)

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
        let reloadedEntry = try XCTUnwrap(TestDiaryStore(fileURL: fileURL).entries(on: day).first)
        XCTAssertEqual(reloadedEntry.nutrients.calories, 150, accuracy: 0.001)
    }

    @MainActor
    func testLoggedMealIngredientEditUpdatesOnlyThatEntry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = TestDiaryStore(fileURL: fileURL)
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

        let toast = food("Toast", calories: 100)
        let eggs = food("Eggs", calories: 200)
        let meal = try XCTUnwrap(store.saveMeal(
            name: "Breakfast",
            items: [
                MealItem(id: UUID(), food: toast, amount: 100, unit: .grams),
                MealItem(id: UUID(), food: eggs, amount: 100, unit: .grams)
            ]
        ))
        store.logMeal(meal, on: day)
        let logged = try XCTUnwrap(store.entries(on: day).first)
        var editedItems = try XCTUnwrap(logged.mealItems)
        editedItems[0].amount = 150

        store.updateMealEntry(entryID: logged.id, amount: logged.amount, items: editedItems)

        let editedEntry = try XCTUnwrap(store.entries(on: day).first)
        XCTAssertNil(editedEntry.savedMealID)
        XCTAssertEqual(editedEntry.mealItems?.map(\.amount) ?? [], [150, 100])
        XCTAssertEqual(editedEntry.nutrients.calories, 350, accuracy: 0.001)
        XCTAssertEqual(store.document.meals.first?.items.map(\.amount) ?? [], [100, 100])
    }

    @MainActor
    func testRenamingMealUpdatesSavedMealAndLoggedEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let day = Date()
        let store = TestDiaryStore(fileURL: fileURL)
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
        XCTAssertEqual(TestDiaryStore(fileURL: fileURL).document.meals.first?.name, "New breakfast")
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
            .appendingPathComponent("diary.sqlite")

        let store = TestDiaryStore(
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
        let store = TestDiaryStore(
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
        let store = TestDiaryStore(
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
        let store = TestDiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        store.log(testFood(calories: 200, name: "Dinner"), amount: 1, unit: .serving, on: day)

        store.setAlcohol(drinks: 2, type: nil, on: day)

        let entry = try XCTUnwrap(store.alcoholEntry(on: day))
        XCTAssertEqual(entry.drinks, 2)
        XCTAssertNil(entry.type)
        XCTAssertEqual(entry.caloriesPerDrink, 150)
        XCTAssertEqual(store.totals(on: day).calories, 500, accuracy: 0.001)
        XCTAssertEqual(store.caloriesExcludingAlcohol(on: day), 200, accuracy: 0.001)

        let reloaded = TestDiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        let reloadedEntry = try XCTUnwrap(reloaded.alcoholEntry(on: day))
        XCTAssertEqual(reloaded.document.schemaVersion, 8)
        XCTAssertEqual(reloadedEntry.id, entry.id)
        XCTAssertEqual(reloadedEntry.date, entry.date)
        XCTAssertEqual(reloadedEntry.drinks, entry.drinks)
        XCTAssertEqual(reloadedEntry.type, entry.type)
        XCTAssertEqual(reloadedEntry.loggedAt.timeIntervalSince(entry.loggedAt), 0, accuracy: 1)
        XCTAssertEqual(reloaded.totals(on: day).calories, 500, accuracy: 0.001)
        XCTAssertEqual(reloaded.caloriesExcludingAlcohol(on: day), 200, accuracy: 0.001)
    }

    @MainActor
    func testAlcoholQuickEntryKeepsOneTypeAndCanBeCleared() {
        let day = testDate(day: 1)
        let store = TestDiaryStore(
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
        let store = TestDiaryStore(
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
    func testCalorieAdjustmentWorksOnNormalDayAndPersists() throws {
        let day = testDate(day: 1)
        let fileURL = temporaryDiaryURL()
        let store = TestDiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        store.log(testFood(calories: 450, name: "Breakfast"), amount: 1, unit: .serving, on: day)

        store.setCalorieAdjustment(1_000, on: day)

        XCTAssertNil(store.status(on: day))
        XCTAssertEqual(store.calorieAdjustment(on: day), 1_000)
        XCTAssertEqual(store.totals(on: day).calories, 1_450, accuracy: 0.001)
        XCTAssertEqual(store.entries(on: day).filter(\.isCheatDayAdjustment).count, 1)

        store.setCalorieAdjustment(1_500, on: day)

        XCTAssertEqual(store.calorieAdjustment(on: day), 1_500)
        XCTAssertEqual(store.totals(on: day).calories, 1_950, accuracy: 0.001)
        XCTAssertEqual(store.entries(on: day).filter(\.isCheatDayAdjustment).count, 1)
        let reloaded = TestDiaryStore(fileURL: fileURL, calendar: testCalendar, referenceDate: day)
        XCTAssertEqual(reloaded.calorieAdjustment(on: day), 1_500)

        reloaded.setCalorieAdjustment(nil, on: day)

        XCTAssertNil(reloaded.status(on: day))
        XCTAssertEqual(reloaded.entries(on: day).map(\.food.name), ["Breakfast"])
        XCTAssertEqual(reloaded.totals(on: day).calories, 450, accuracy: 0.001)
    }

    @MainActor
    func testUndoingCheatDayPreservesIndependentCalorieAdjustment() throws {
        let day = testDate(day: 1)
        let store = TestDiaryStore(
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: day
        )
        store.log(testFood(calories: 450, name: "Breakfast"), amount: 1, unit: .serving, on: day)
        store.setCalorieAdjustment(1_000, on: day)
        store.markCheatDay(on: day)

        XCTAssertEqual(store.status(on: day)?.kind, .cheat)
        XCTAssertEqual(store.calorieAdjustment(on: day), 1_000)

        store.undoCheatDay(on: day, preservingCalorieAdjustment: true)

        XCTAssertNil(store.status(on: day))
        XCTAssertEqual(store.calorieAdjustment(on: day), 1_000)
        XCTAssertEqual(store.totals(on: day).calories, 1_450, accuracy: 0.001)
    }

    @MainActor
    func testUndoingCheatDayRemovesAdjustmentByDefault() {
        let day = testDate(day: 1)
        let store = TestDiaryStore(
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: day
        )
        store.setCalorieAdjustment(1_000, on: day)
        store.markCheatDay(on: day)

        store.undoCheatDay(on: day)

        XCTAssertNil(store.status(on: day))
        XCTAssertNil(store.calorieAdjustment(on: day))
        XCTAssertEqual(store.totals(on: day).calories, 0, accuracy: 0.001)
    }

    @MainActor
    func testStreakSummaryUsesConsecutiveLoggedDaysEvenOnCheatDays() {
        let days = (1...3).map { testDate(day: $0) }
        var document = DiaryDocument()
        document.trackingStartDate = days[0]
        document.entries = [
            testEntry(calories: 1_800, date: days[0], name: "Toast"),
            testEntry(calories: 2_000, date: days[1], name: "Toast")
        ]
        let store = TestDiaryStore(
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
        XCTAssertEqual(store.streak(referenceDate: days[2]).dayCount, 2)
    }

    @MainActor
    func testStreakSummaryListsFrequentFoodsByCount() {
        let days = (1...3).map { testDate(day: $0) }
        var document = DiaryDocument()
        document.trackingStartDate = days[0]
        document.entries = [
            testEntry(calories: 100, date: days[0], name: "Toast"),
            testEntry(calories: 100, date: days[1], name: "Toast"),
            testEntry(calories: 100, date: days[0], name: "Eggs"),
            testEntry(calories: 100, date: days[1], name: "Apple")
        ]
        let store = TestDiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: days[2]
        )

        XCTAssertEqual(
            store.streak(referenceDate: days[2]).frequentFoods,
            [
                FrequentFood(name: "Toast", count: 2),
                FrequentFood(name: "Apple", count: 1),
                FrequentFood(name: "Eggs", count: 1)
            ]
        )
    }

    @MainActor
    func testStreakRequiresFoodOrMealAndIgnoresAlcoholOnlyDays() {
        let days = (1...3).map { testDate(day: $0) }
        var document = DiaryDocument()
        document.trackingStartDate = days[0]
        document.entries = [testEntry(calories: 1_800, date: days[0], name: "Toast")]
        document.alcoholEntries = [AlcoholEntry(
            id: UUID(),
            date: days[1],
            drinks: 1,
            type: .wine,
            loggedAt: days[1]
        )]
        let store = TestDiaryStore(
            document: document,
            fileURL: temporaryDiaryURL(),
            calendar: testCalendar,
            referenceDate: days[2]
        )

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
            "proteinGrams": 60,
            "fiberGrams": 8
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
        XCTAssertEqual(food.nutrients.fiber, 8)
        XCTAssertEqual(food.servingGrams, 510)
        XCTAssertEqual(food.availablePortions.first?.label, "whole bowl")
        XCTAssertEqual(food.nutrients(for: 1, unit: .serving, portionID: "imported-serving"), food.nutrients)
    }

    @MainActor
    func testOneOffImportedFoodLogsWithoutSavingCustomFood() throws {
        let fileURL = temporaryDiaryURL()
        let store = TestDiaryStore(fileURL: fileURL)
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
        XCTAssertEqual(meal.origin, .imported)
        XCTAssertEqual(meal.items.map(\.food.name), ["Chicken", "Rice"])
        XCTAssertEqual(meal.items.map(\.food.servingGrams), [170, 190])
        XCTAssertEqual(meal.nutrients, MacroNutrients(calories: 540, carbs: 52, fat: 13, protein: 50))
    }

    @MainActor
    func testOneOffImportedMealIsBreakableWithoutSavingMealOrFoods() throws {
        let fileURL = temporaryDiaryURL()
        let store = TestDiaryStore(fileURL: fileURL)
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

    @MainActor
    func testOneOffImportedMealRemainsDetachedAfterReload() throws {
        let fileURL = temporaryDiaryURL()
        let store = TestDiaryStore(fileURL: fileURL)
        let food = Food(
            sourceID: "legacy-imported-food",
            source: .custom,
            name: "Rice",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 240, carbs: 52, fat: 1, protein: 5),
            baseAmountGrams: 190,
            servingGrams: 190,
            servingDescription: "cup"
        )
        let meal = SavedMeal(
            id: UUID(),
            name: "Imported rice",
            items: [MealItem(id: UUID(), food: food, amount: 1, unit: .serving)],
            origin: .imported
        )
        store.logOneOffMeal(meal, on: Date())

        let reloaded = TestDiaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.customMeals.count, 0)
        XCTAssertTrue(reloaded.importedMeals.isEmpty)
        let entry = try XCTUnwrap(reloaded.entries(on: Date()).first)
        XCTAssertNil(entry.savedMealID)
        XCTAssertEqual(entry.food.name, "Imported rice")
        XCTAssertEqual(entry.mealItems?.map(\.food.name), ["Rice"])
    }

    @MainActor
    func testImportedMealIsRetainedForRecentButExcludedFromCustomMeals() throws {
        let store = TestDiaryStore(fileURL: temporaryDiaryURL())
        let food = Food(
            sourceID: "imported-food",
            source: .custom,
            name: "Chicken",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 300, carbs: 0, fat: 12, protein: 45),
            baseAmountGrams: 170,
            servingGrams: 170,
            servingDescription: "portion"
        )
        let item = MealItem(id: UUID(), food: food, amount: 1, unit: .serving)
        let customMeal = try XCTUnwrap(store.saveMeal(name: "Hand breakfast", items: [item]))
        let importedMeal = try XCTUnwrap(store.saveMeal(
            name: "Imported lunch",
            items: [item],
            origin: .imported
        ))

        store.logMeal(importedMeal, on: Date())

        XCTAssertEqual(store.customMeals.map(\.id), [customMeal.id])
        XCTAssertEqual(store.importedMeals.map(\.id), [importedMeal.id])
        XCTAssertEqual(store.recentItems, [.meal(importedMeal)])
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

    func testQuickLogRecentNameResolutionUsesMostRecentExactMatch() {
        let older = testFood(calories: 80, name: "Cappuccino")
        var newer = testFood(calories: 120, name: "Cappuccino")
        newer = Food(
            sourceID: "newer-cappuccino",
            source: newer.source,
            name: newer.name,
            brand: newer.brand,
            barcode: newer.barcode,
            nutrients: newer.nutrients,
            baseAmountGrams: newer.baseAmountGrams,
            servingGrams: newer.servingGrams,
            servingDescription: newer.servingDescription,
            portions: newer.portions
        )
        var document = DiaryDocument()
        document.entries = [
            DiaryEntry(
                id: UUID(),
                date: testDate(day: 10),
                food: older,
                amount: 1,
                unit: .serving,
                nutrients: older.nutrients,
                loggedAt: testDate(day: 10),
                portionID: "serving"
            ),
            DiaryEntry(
                id: UUID(),
                date: testDate(day: 11),
                food: newer,
                amount: 1,
                unit: .serving,
                nutrients: newer.nutrients,
                loggedAt: testDate(day: 11),
                portionID: "serving"
            )
        ]
        let matches = QuickLogSnapshot(document: document, calendar: testCalendar)
            .recentSelections(matching: "cappuccino")

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.id, "food:\(newer.id)")
    }

    func testQuickLogRecentNameResolutionSupportsArticlesAndCompoundRequests() {
        let cappuccino = testFood(calories: 120, name: "Cappuccino")
        let feta = testFood(calories: 80, name: "Feta Cheese")
        var document = DiaryDocument()
        document.entries = [
            DiaryEntry(
                id: UUID(),
                date: testDate(day: 10),
                food: cappuccino,
                amount: 1,
                unit: .serving,
                nutrients: cappuccino.nutrients,
                loggedAt: testDate(day: 10),
                portionID: "serving"
            ),
            DiaryEntry(
                id: UUID(),
                date: testDate(day: 11),
                food: feta,
                amount: 1,
                unit: .serving,
                nutrients: feta.nutrients,
                loggedAt: testDate(day: 11),
                portionID: "serving"
            )
        ]
        document.rememberedQuantities = [
            cappuccino.id: QuantityPreference(amount: 1, unit: .serving, portionID: "serving"),
            feta.id: QuantityPreference(amount: 1, unit: .serving, portionID: "serving")
        ]

        let matches = QuickLogSnapshot(document: document, calendar: testCalendar)
            .recentSelections(matching: "a cappuccino and feta cheese")

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(Set(matches[0].itemIDs), Set(["food:\(cappuccino.id)", "food:\(feta.id)"]))
        XCTAssertEqual(matches[0].subtitle, "200 cal")
    }

    func testQuickLogRepositoryLogsRememberedQuantityWithoutOpeningApp() throws {
        let fileURL = temporaryDiaryURL()
        let food = testFood(calories: 90, name: "Cappuccino")
        let historyDate = testDate(day: 10)
        let logDate = testDate(day: 12)
        var document = DiaryDocument()
        document.trackingStartDate = historyDate
        document.entries = [DiaryEntry(
            id: UUID(),
            date: historyDate,
            food: food,
            amount: 1,
            unit: .serving,
            nutrients: food.nutrients,
            loggedAt: historyDate,
            portionID: "serving"
        )]
        document.rememberedQuantities[food.id] = QuantityPreference(
            amount: 2,
            unit: .serving,
            portionID: "serving"
        )
        try write(document, to: fileURL)

        let result = try QuickLogRepository(fileURL: fileURL, calendar: testCalendar)
            .log(selectionID: "food:\(food.id)", at: logDate)
        let saved = try readDiary(from: fileURL)
        let loggedEntry = try XCTUnwrap(saved.entries.first {
            testCalendar.isDate($0.date, inSameDayAs: logDate)
        })

        XCTAssertEqual(result, QuickLogResult(title: "Cappuccino", loggedItemCount: 1, selectionID: "food:custom:cappuccino"))
        XCTAssertEqual(loggedEntry.amount, 2)
        XCTAssertEqual(loggedEntry.nutrients.calories, 180)
    }

    func testQuickLogCaloriesRemainingIncludesFoodAndAlcohol() throws {
        let date = testDate(day: 12)
        var document = DiaryDocument()
        document.dailyCalorieGoal = 2_000
        document.entries = [testEntry(calories: 650, date: date, name: "Lunch")]
        document.alcoholEntries = [AlcoholEntry(
            id: UUID(),
            date: date,
            drinks: 1,
            type: .wine,
            loggedAt: date
        )]

        let remaining = try QuickLogSnapshot(document: document, calendar: testCalendar)
            .caloriesRemaining(at: date)

        XCTAssertEqual(remaining, 1_225)
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

    private func write(_ document: DiaryDocument, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try DiaryRepository(fileURL: fileURL).importDocument(document)
    }

    private func readDiary(from fileURL: URL) throws -> DiaryDocument {
        try DiaryRepository(fileURL: fileURL).snapshotSync().document
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

@MainActor
private final class TestDiaryStore: DiaryStore {
    init(fileURL: URL? = nil, calendar: Calendar = .current, catalog: CatalogStore? = nil, healthKit: HealthKitStore? = nil, referenceDate: Date = Date()) {
        super.init(fileURL: fileURL, calendar: calendar, catalog: catalog, healthKit: healthKit, referenceDate: referenceDate, usesWindow: false)
        try! loadTestFixture(referenceDate: referenceDate)
    }
    init(document: DiaryDocument, fileURL: URL? = nil, calendar: Calendar = .current, catalog: CatalogStore? = nil, healthKit: HealthKitStore? = nil, referenceDate: Date = Date()) {
        let url = fileURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        super.init(fileURL: url, calendar: calendar, catalog: catalog, healthKit: healthKit, referenceDate: referenceDate, usesWindow: false)
        try! DiaryRepository(fileURL: url, calendar: calendar).importDocument(DiaryEngine.backfilledFoodMetadata(in: document, catalog: catalog))
        try! loadTestFixture(referenceDate: referenceDate)
    }
    func setAlcohol(drinks: Int, type: AlcoholType?, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.setAlcohol(drinks: drinks, type: type, on: date) }
    }
    func setDailyCalorieGoal(_ goal: Int?) {
        try! performTestMutation(scope: .all) { $0.setDailyCalorieGoal(goal) }
    }
    func markCheatDay(on date: Date, adjustmentCalories: Int? = nil) {
        try! performTestMutation(scope: .day(date)) { $0.markCheatDay(on: date, adjustmentCalories: adjustmentCalories) }
    }
    func setCalorieAdjustment(_ calories: Int?, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.setCalorieAdjustment(calories, on: date) }
    }
    func undoCheatDay(on date: Date, preservingCalorieAdjustment: Bool = false) {
        try! performTestMutation(scope: .day(date)) { $0.undoCheatDay(on: date, preservingCalorieAdjustment: preservingCalorieAdjustment) }
    }
    func finalizePastDays(referenceDate: Date = Date()) {
        try! performTestMutation(scope: .all) { $0.finalizePastDays(referenceDate: referenceDate) }
    }
#if DEBUG
    func seedSpecialDaysForScreenshots(referenceDate: Date = Date()) {
        try! performTestMutation(scope: .window(reference: referenceDate, selectedDay: nil)) { $0.seedSpecialDaysForScreenshots(referenceDate: referenceDate) }
    }
#endif
    func log(_ food: Food, amount: Double, unit: LogUnit, portionID: String? = nil, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.log(food, amount: amount, unit: unit, portionID: portionID, on: date) }
    }
    func delete(entryID: UUID) {
        try! performTestMutation(scope: .entries([entryID])) { $0.delete(entryID: entryID) }
    }
    func deleteEntries(entryIDs: Set<UUID>) {
        try! performTestMutation(scope: .entries(entryIDs)) { $0.deleteEntries(entryIDs: entryIDs) }
    }
    func updateEntry(entryID: UUID,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil) {
        try! performTestMutation(scope: .entries([entryID])) { $0.updateEntry(entryID: entryID, amount: amount, unit: unit, portionID: portionID) }
    }
    func moveEntry(_ entryID: UUID,
        relativeTo targetEntryID: UUID,
        placeAfterTarget: Bool,
        on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.moveEntry(entryID, relativeTo: targetEntryID, placeAfterTarget: placeAfterTarget, on: date) }
    }
    func moveEntry(_ entryID: UUID, toIndex destinationIndex: Int, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.moveEntry(entryID, toIndex: destinationIndex, on: date) }
    }
    func rememberPreference(_ preference: QuantityPreference, for food: Food) {
        try! performTestMutation(scope: .library) { $0.rememberPreference(preference, for: food) }
    }
    func quickLog(_ food: Food, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.quickLog(food, on: date) }
    }
    @discardableResult
    func logMagicSuggestion(_ suggestion: MagicFoodSuggestion, on date: Date) -> [FoodPickerItem] {
        try! performTestMutation(scope: .window(reference: date, selectedDay: date)) { $0.logMagicSuggestion(suggestion, on: date) }
    }
    @discardableResult
    func logQuickSelection(_ selectionID: String, on date: Date = Date()) -> QuickLogResult? {
        try! performTestMutation(scope: .window(reference: date, selectedDay: date)) { $0.logQuickSelection(selectionID, on: date) }
    }
    func toggleFavorite(_ food: Food, preference: QuantityPreference? = nil) {
        try! performTestMutation(scope: .library) { $0.toggleFavorite(food, preference: preference) }
    }
    func toggleFavorite(_ meal: SavedMeal) {
        try! performTestMutation(scope: .library) { $0.toggleFavorite(meal) }
    }
    @discardableResult
    func addCustomFood(name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil,
        servingGrams: Double,
        servingDescription: String = "1 serving",
        containsProcessedMeat: Bool = false,
        containsRedMeat: Bool = false) -> Food {
        try! performTestMutation(scope: .library) { $0.addCustomFood(name: name, brand: brand, calories: calories, carbs: carbs, fat: fat, protein: protein, fiber: fiber, servingGrams: servingGrams, servingDescription: servingDescription, containsProcessedMeat: containsProcessedMeat, containsRedMeat: containsRedMeat) }
    }
    @discardableResult
    func updateCustomFood(foodID: String,
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil,
        servingGrams: Double,
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil) -> Bool {
        try! performTestMutation(scope: .food(foodID)) { $0.updateCustomFood(foodID: foodID, name: name, brand: brand, calories: calories, carbs: carbs, fat: fat, protein: protein, fiber: fiber, servingGrams: servingGrams, containsProcessedMeat: containsProcessedMeat, containsRedMeat: containsRedMeat) }
    }
    @discardableResult
    func saveMeal(name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        origin: SavedMealOrigin = .custom) -> SavedMeal? {
        try! performTestMutation(scope: .library) { $0.saveMeal(name: name, items: items, containsProcessedMeat: containsProcessedMeat, containsRedMeat: containsRedMeat, origin: origin) }
    }
    @discardableResult
    func updateSavedMeal(mealID: UUID,
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil) -> Bool {
        try! performTestMutation(scope: .meal(mealID)) { $0.updateSavedMeal(mealID: mealID, name: name, items: items, containsProcessedMeat: containsProcessedMeat, containsRedMeat: containsRedMeat) }
    }
    func saveMeal(name: String, replacing entryIDs: Set<UUID>, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.saveMeal(name: name, replacing: entryIDs, on: date) }
    }
    func breakApartMeal(entryID: UUID) {
        try! performTestMutation(scope: .entries([entryID])) { $0.breakApartMeal(entryID: entryID) }
    }
    func deleteCustomFood(_ food: Food) {
        try! performTestMutation(scope: .library) { $0.deleteCustomFood(food) }
    }
    func deleteMeal(_ meal: SavedMeal) {
        try! performTestMutation(scope: .library) { $0.deleteMeal(meal) }
    }
    func logMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.logMeal(meal, amount: amount, on: date) }
    }
    func logOneOffMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date) {
        try! performTestMutation(scope: .day(date)) { $0.logOneOffMeal(meal, amount: amount, on: date) }
    }
    func updateMealEntry(entryID: UUID, amount: Double) {
        try! performTestMutation(scope: .entries([entryID])) { $0.updateMealEntry(entryID: entryID, amount: amount) }
    }
    func updateMealEntry(entryID: UUID, amount: Double, items: [MealItem]) {
        try! performTestMutation(scope: .entries([entryID])) { $0.updateMealEntry(entryID: entryID, amount: amount, items: items) }
    }
    @discardableResult
    func renameMeal(mealID: UUID, name: String) -> Bool {
        try! performTestMutation(scope: .meal(mealID)) { $0.renameMeal(mealID: mealID, name: name) }
    }
    @discardableResult
    func renameFood(foodID: String, name: String) -> Bool {
        try! performTestMutation(scope: .food(foodID)) { $0.renameFood(foodID: foodID, name: name) }
    }
    func clearPersonalData() {
        try! performTestMutation(scope: .all) { $0.clearPersonalData() }
    }
}

@MainActor
private final class TestSnackRemindersClient: SnackRemindersClient {
    var hasAccess = false
    var accessRequests = 0
    var accessError: Error?
    var fetchError: Error?
    var saveError: Error?
    var onFetch: (() async -> Void)?
    var availableLists: [SnackReminderList] = [
        .init(id: "personal", title: "Personal", account: "On My iPhone"),
        .init(id: "groceries", title: "Groceries", account: "iCloud")
    ]
    var existing: [String: [ExistingSnackReminder]] = [:]
    var fetchedListIDs: [String] = []
    var savedBatches: [(listID: String, snacks: [SnackSuggestion])] = []

    func requestAccess() async throws {
        accessRequests += 1
        if let accessError { throw accessError }
        hasAccess = true
    }

    func writableLists() -> [SnackReminderList] { hasAccess ? availableLists : [] }

    func incompleteReminders(in listID: String) async throws -> [ExistingSnackReminder] {
        if let fetchError { throw fetchError }
        fetchedListIDs.append(listID)
        await onFetch?()
        return existing[listID] ?? []
    }

    func save(_ snacks: [SnackSuggestion], to listID: String) throws {
        if let saveError { throw saveError }
        savedBatches.append((listID, snacks))
        existing[listID, default: []].append(contentsOf: snacks.map {
            ExistingSnackReminder(title: $0.name, url: $0.reminderURL)
        })
    }
}
