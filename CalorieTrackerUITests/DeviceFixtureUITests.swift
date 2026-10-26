import XCTest

final class DeviceFixtureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testSearchResultUsesRememberedChaseFoodUnitInCustomization() {
        app.launchArguments = [
            "-onboarding.focus.v1.completed", "YES",
            "-foodSource.enabled.chaseFood", "YES",
            "-foodSource.enabled.usda", "YES",
            "-foodSource.enabled.off", "YES"
        ]
        app.launchEnvironment = [
            "CALORIE_TRACKER_UNIFIED_FIXTURE": "1",
            "CALORIE_TRACKER_FIXTURE_RESET": "1"
        ]
        app.launch()

        let logFood = app.buttons["Log food"]
        XCTAssertTrue(logFood.waitForExistence(timeout: 10))
        logFood.tap()
        let search = app.textFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("sandwich")
        let result = app.buttons["customize-food-chaseFood:food_sandwich"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()

        let unit = app.buttons["custom-food-unit-picker"]
        XCTAssertTrue(unit.waitForExistence(timeout: 5))
        XCTAssertEqual(unit.value as? String, "grams")
        XCTAssertEqual(app.textFields["custom-food-quantity-value"].value as? String, "275")
    }

    func testSearchFoodCanBeHiddenAndRestoredFromSettings() {
        app.launchArguments = [
            "--show-food-search",
            "-foodSource.enabled.chaseFood", "YES",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launchEnvironment = [
            "CALORIE_TRACKER_UNIFIED_FIXTURE": "1",
            "CALORIE_TRACKER_FIXTURE_RESET": "1"
        ]
        app.launch()

        let search = app.textFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "sandwich")

        let sandwich = app.buttons["customize-food-chaseFood:food_sandwich"]
        XCTAssertTrue(sandwich.waitForExistence(timeout: 10))
        sandwich.press(forDuration: 1)
        let hideAction = app.buttons["hide-search-food-chaseFood:food_sandwich"]
        XCTAssertTrue(hideAction.waitForExistence(timeout: 5))
        hideAction.tap()
        let confirmHide = app.buttons.matching(identifier: "confirm-hide-search-food").firstMatch
        XCTAssertTrue(confirmHide.waitForExistence(timeout: 5))
        confirmHide.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !sandwich.exists })

        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Hidden Foods"].tap()
        let restore = app.buttons["Restore Sandwich to search"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { app.staticTexts["No Hidden Foods"].exists })

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Log food"].tap()
        let restoredSearch = app.textFields["Search foods"]
        XCTAssertTrue(restoredSearch.waitForExistence(timeout: 5))
        restoredSearch.tap()
        restoredSearch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "sandwich")
        XCTAssertTrue(app.buttons["customize-food-chaseFood:food_sandwich"].waitForExistence(timeout: 10))
    }

    func testNoResultSearchCanOpenPrefilledAIEstimate() {
        let query = "unlisted dragonfruit snack"
        app.launchArguments = [
            "--show-food-search",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launchEnvironment = [
            "CALORIE_TRACKER_UNIFIED_FIXTURE": "1",
            "CALORIE_TRACKER_FIXTURE_RESET": "1"
        ]
        app.launch()

        let search = app.textFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + query)

        let estimate = app.buttons["Estimate with AI"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        estimate.tap()

        let descriptions = app.descendants(matching: .any).matching(identifier: "Meal description")
        XCTAssertTrue(descriptions.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(descriptions.allElementsBoundByIndex.contains { ($0.value as? String) == query })
        XCTAssertTrue(app.buttons["Analyze Meal"].exists)
    }

    func testDeviceFixtureShowsRelativeDays() {
        app.launchArguments = ["--show-scrolled-diary", "-onboarding.focus.v1.completed", "YES"]
        app.launchEnvironment = [
            "CALORIE_TRACKER_FIXTURE": "device",
            "CALORIE_TRACKER_FIXTURE_RESET": "1"
        ]
        app.launch()

        let loggedFoods = app.descendants(matching: .any)
            .matching(identifier: "logged-foods-reorder-list")
            .firstMatch
        XCTAssertTrue(loggedFoods.waitForExistence(timeout: 5))
        XCTAssertTrue((loggedFoods.value as? String ?? "").contains("Plum, raw"))
        assertDiaryLayout(firstEntrySourceID: "2709265")

        app.buttons["Log food"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let magicFoodNames = [
            "Cappuccino",
            "Protein shake",
            "Turkey sandwich",
            "Tea with honey",
            "Chili, no rice",
            "Rice, white, cooked, glutinous"
        ]
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label IN %@", magicFoodNames)
        ).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(loggedFoods.waitForExistence(timeout: 3))
        assertDiaryLayout(firstEntrySourceID: "2709265")

        let yesterday = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Yesterday'")
        ).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 3))
        yesterday.tap()
        XCTAssertTrue((loggedFoods.value as? String ?? "").contains("Chili, no rice"))
        assertDiaryLayout(firstEntrySourceID: "saved-meal-32B0CAC9-90A2-4CB1-932A-70F837708E83")

        let tomorrow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Tomorrow'")
        ).firstMatch
        tomorrow.tap()
        XCTAssertTrue((loggedFoods.value as? String ?? "").contains("Plum, raw"))
        XCTAssertFalse(app.staticTexts["Nothing logged"].exists)
    }

    func testSnackSuggestionsSelectionWithoutRemindersAccess() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES",
                               "-trends.focus.fiber", "NO", "-trends.focus.processedMeat", "NO",
                               "-trends.focus.redMeat", "NO", "-trends.focus.alcohol", "NO"]
        app.launchEnvironment = ["CALORIE_TRACKER_FIXTURE": "device", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Snack Suggestions"].waitForExistence(timeout: 3))
        app.buttons["Snack Suggestions"].tap()
        XCTAssertTrue(app.navigationBars["Snack Suggestions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0 selected"].exists)
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.staticTexts["12 selected"].exists, "Only always-included protein picks should be selected")
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.staticTexts["0 selected"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Browsing and selection must not request permission")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Snack Suggestions — Protein Only"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testMagicGroupedSuggestionItemsOpenCustomization() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES"]
        app.launchEnvironment = ["CALORIE_TRACKER_FIXTURE": "device", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Log food"].waitForExistence(timeout: 5))
        app.buttons["Log food"].tap()
        let sandwich = app.buttons.matching(NSPredicate(format: "label == %@", "Customize Turkey sandwich")).firstMatch
        XCTAssertTrue(sandwich.waitForExistence(timeout: 5), "Each item inside a Magic suggestion should be independently tappable")
        sandwich.tap()
        XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["custom-food-sticky-title"].label, "Turkey sandwich")
        XCTAssertTrue(app.buttons["custom-food-back"].exists)
    }

    func testCheatDayConfirmationCapsuleAcceptsEdgeTap() {
        launchCheatDayFixture(reset: true)
        app.buttons["cheat-day-toolbar"].tap()
        let confirmation = app.buttons["cheat-day-confirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        // The visible capsule must respond beyond the text glyphs.
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Undo cheat day"].waitForExistence(timeout: 3))
        XCTAssertFalse(confirmation.exists)
    }

    func testCheatDayRepeatedConfirmationAndEntryPoints() {
        launchCheatDayFixture(reset: true)
        let loggedFoods = app.descendants(matching: .any)
            .matching(identifier: "logged-foods-reorder-list").firstMatch
        XCTAssertTrue(loggedFoods.waitForExistence(timeout: 3))
        let originalFoods = loggedFoods.value as? String
        for cycle in 0..<20 {
            app.buttons["cheat-day-toolbar"].tap()
            confirmCheatDay(expectedCheat: true, doubleTap: cycle == 0)
            XCTAssertEqual(loggedFoods.value as? String, originalFoods)
            switch cycle % 5 {
            case 0:
                app.buttons["cheat-day-toolbar"].tap()
            case 1:
                app.buttons["cheat-day-banner"].tap()
            case 2:
                app.buttons["Log food"].tap()
            case 3:
                app.buttons["Log alcohol"].tap()
            default:
                app.descendants(matching: .any).matching(identifier: "diary-entry-2709265")
                    .firstMatch.tap()
            }
            confirmCheatDay(expectedCheat: false, doubleTap: cycle == 0)
            XCTAssertEqual(loggedFoods.value as? String, originalFoods)
        }
        // Keep the fixture database on relaunch to verify both transitions persist.
        app.buttons["cheat-day-toolbar"].tap()
        confirmCheatDay(expectedCheat: true)
        app.terminate()
        launchCheatDayFixture(reset: false)
        XCTAssertEqual(app.buttons["cheat-day-toolbar"].label, "Undo cheat day")
        app.buttons["cheat-day-toolbar"].tap()
        confirmCheatDay(expectedCheat: false)
        app.terminate()
        launchCheatDayFixture(reset: false)
        XCTAssertEqual(app.buttons["cheat-day-toolbar"].label, "Mark cheat day")

        // Confirm a past date and ensure today is not accidentally changed.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yesterday'"))
            .firstMatch.tap()
        let wasCheat = app.buttons["cheat-day-toolbar"].label == "Undo cheat day"
        app.buttons["cheat-day-toolbar"].tap()
        confirmCheatDay(expectedCheat: !wasCheat)
        app.buttons["cheat-day-toolbar"].tap()
        confirmCheatDay(expectedCheat: wasCheat)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tomorrow'"))
            .firstMatch.tap()
        XCTAssertEqual(app.buttons["cheat-day-toolbar"].label, "Mark cheat day")
    }

    func testLoggedFoodReturnsToSharedCustomizationAndNestedCancelIsSafe() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES",
            "-foodSource.enabled.chaseFood", "YES", "-foodSource.enabled.usda", "NO", "-foodSource.enabled.off", "NO"]
        app.launchEnvironment = ["CALORIE_TRACKER_FIXTURE": "device", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Log food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "logged-foods-reorder-list").firstMatch.waitForExistence(timeout: 10))
        let logFood = app.buttons["Log food"]
        logFood.tap()
        let search = app.textFields["Search foods"]
        if !search.waitForExistence(timeout: 3), logFood.exists {
            logFood.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(search.exists)
        search.tap(); search.typeText("sandwich")
        let customize = app.buttons["Customize Sandwich"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        customize.tap()
        XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 3))
        let initialCalories = visibleCaloriesLabel()
        app.buttons["Log Food"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let logged = app.descendants(matching: .any).matching(identifier: "diary-entry-food_sandwich").firstMatch
        XCTAssertTrue(logged.waitForExistence(timeout: 5))
        let loggedList = app.descendants(matching: .any).matching(identifier: "logged-foods-reorder-list").firstMatch
        let loggedOrder = loggedList.value as? String
        XCTAssertNotNil(loggedOrder)
        logged.tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 3))
        XCTAssertEqual(visibleCaloriesLabel(), initialCalories)
        XCTAssertFalse(app.buttons["customization-edit-title"].exists)
        app.buttons["custom-food-recent-variations"].tap()
        app.buttons["Rename"].tap()
        let titleField = app.textFields["customization-name-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        XCTAssertEqual(titleField.value as? String, "Sandwich")
        app.buttons["customization-name-save"].tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Logged Sandwich — Shared customization"
        attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["custom-food-add-ingredient"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("avocado")
        let avocadoAdd = app.buttons.matching(NSPredicate(format: "label == %@", "Add Avocado")).firstMatch
        XCTAssertTrue(avocadoAdd.waitForExistence(timeout: 5))
        avocadoAdd.tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5), "Plus should add directly to the parent and close search")
        XCTAssertNotEqual(visibleCaloriesLabel(), initialCalories)
        let avocadoCustomize = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'meal-component-edit-'" )).firstMatch
        XCTAssertTrue(avocadoCustomize.waitForExistence(timeout: 3))
        avocadoCustomize.tap()
        XCTAssertTrue(app.textFields["meal-component-quantity-value"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["meal-component-quantity-unit"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 3))
        // Cancel the parent; its newly added ingredient must not reach the diary.
        app.buttons["custom-food-add-ingredient"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("avocado")
        XCTAssertTrue(avocadoAdd.waitForExistence(timeout: 5)); avocadoAdd.tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5))
        visibleButton("custom-food-back").tap()
        XCTAssertTrue(logged.waitForExistence(timeout: 5)); logged.tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 3))
        XCTAssertEqual(visibleCaloriesLabel(), initialCalories)
        visibleButton("custom-food-quantity-plus").tap()
        let changedCalories = visibleCaloriesLabel()
        XCTAssertNotEqual(changedCalories, initialCalories)
        app.buttons["Save changes"].tap()
        XCTAssertTrue(logged.waitForExistence(timeout: 5))
        XCTAssertEqual(loggedList.value as? String, loggedOrder, "Saving must preserve entry count and order")
        app.terminate()
        app.launchEnvironment["CALORIE_TRACKER_FIXTURE_RESET"] = "0"
        app.launchEnvironment["CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(logged.waitForExistence(timeout: 5))
        logged.tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 3))
        XCTAssertEqual(visibleCaloriesLabel(), changedCalories)
        let savedAttachment = XCTAttachment(screenshot: app.screenshot())
        savedAttachment.name = "Logged Sandwich — Saved changes after relaunch"
        savedAttachment.lifetime = .keepAlways; add(savedAttachment)
        visibleButton("custom-food-back").tap()
    }

    func testLoggedFoodMeatClassificationChoicesPersistIndependently() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES"]
        app.launchEnvironment = ["CALORIE_TRACKER_FIXTURE": "device", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
        app.launch()

        let entry = app.descendants(matching: .any).matching(identifier: "diary-entry-2709265").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5))

        let processedMeat = app.buttons["logged-food-processed-meat"]
        let redMeat = app.buttons["logged-food-red-meat"]
        for _ in 0..<8 where !processedMeat.isHittable { app.swipeUp() }
        XCTAssertTrue(processedMeat.waitForExistence(timeout: 5))
        XCTAssertTrue(redMeat.waitForExistence(timeout: 5))
        XCTAssertEqual(processedMeat.frame.minY, redMeat.frame.minY, accuracy: 1, "Meat checkboxes should share one row")
        XCTAssertEqual(processedMeat.frame.width, redMeat.frame.width, accuracy: 1, "Meat checkboxes should each use half the row")
        XCTAssertLessThan(processedMeat.frame.maxX, redMeat.frame.minX)
        if !processedMeat.isSelected { processedMeat.tap() }
        if !redMeat.isSelected { redMeat.tap() }
        XCTAssertTrue(processedMeat.isSelected)
        XCTAssertTrue(redMeat.isSelected)
        app.buttons["Save changes"].tap()

        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        for _ in 0..<8 where !processedMeat.isHittable { app.swipeUp() }
        XCTAssertTrue(processedMeat.waitForExistence(timeout: 5))
        XCTAssertTrue(processedMeat.isSelected)
        XCTAssertTrue(redMeat.isSelected)
        redMeat.tap()
        XCTAssertFalse(redMeat.isSelected, "The red-meat checkbox should toggle off independently")
        XCTAssertTrue(processedMeat.isSelected)
        visibleButton("custom-food-back").tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        for _ in 0..<8 where !processedMeat.isHittable { app.swipeUp() }
        XCTAssertTrue(processedMeat.waitForExistence(timeout: 5))
        XCTAssertTrue(processedMeat.isSelected)
        XCTAssertTrue(redMeat.isSelected, "Leaving without saving must discard the pending red-meat change")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Logged Food Meat Classification"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSharedMealCompositionUsesFoodSearchAndCancelsParentDraft() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES",
            "-foodSource.enabled.chaseFood", "YES", "-foodSource.enabled.usda", "NO", "-foodSource.enabled.off", "NO"]
        app.launchEnvironment = ["CALORIE_TRACKER_FIXTURE": "device", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
        app.launch()
        let loggedList = app.descendants(matching: .any).matching(identifier: "logged-foods-reorder-list").firstMatch
        XCTAssertTrue(loggedList.waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yesterday'")).firstMatch.tap()
        let meal = app.descendants(matching: .any).matching(identifier: "diary-entry-saved-meal-32B0CAC9-90A2-4CB1-932A-70F837708E83").firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        let originalOrder = loggedList.value as? String
        meal.tap()
        XCTAssertTrue(app.buttons["meal-detail-save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Meal"].exists || app.staticTexts["custom-food-sticky-title"].exists)
        XCTAssertFalse(app.buttons["customization-edit-title"].exists)
        app.buttons["custom-food-recent-variations"].tap()
        app.buttons["Rename"].tap()
        let mealName = app.textFields["customization-name-field"]
        XCTAssertTrue(mealName.waitForExistence(timeout: 3))
        XCTAssertEqual(mealName.value as? String, "Chili, no rice")
        app.buttons["customization-name-save"].tap()
        XCTAssertTrue(app.buttons["meal-detail-save"].waitForExistence(timeout: 3))
        let mealFoods = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'meal-food-option-'"))
        XCTAssertGreaterThan(mealFoods.count, 0)
        let firstMealFood = mealFoods.firstMatch
        XCTAssertTrue(firstMealFood.isSelected)
        firstMealFood.tap()
        XCTAssertFalse(firstMealFood.isSelected, "Meal foods should toggle off using the shared selection-pill pattern.")
        firstMealFood.tap()
        XCTAssertTrue(firstMealFood.isSelected)
        let originalMealFoodCount = mealFoods.count
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'meal-component-edit-'" )).firstMatch.exists,
            "Meal food units are changed by adding a different food selection.")
        XCTAssertTrue(app.buttons["meal-detail-save"].waitForExistence(timeout: 3))
        for _ in 0..<5 where !app.buttons["meal-detail-add-food"].isHittable { scrollCustomizationBody() }
        XCTAssertTrue(app.buttons["meal-detail-add-food"].waitForExistence(timeout: 3))
        app.buttons["meal-detail-add-food"].tap()
        let search = app.textFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("sandwich")
        let sandwich = app.buttons["customize-food-chaseFood:food_sandwich"]
        XCTAssertTrue(sandwich.waitForExistence(timeout: 5)); sandwich.tap()
        XCTAssertTrue(app.buttons["Add to parent"].waitForExistence(timeout: 3))
        app.buttons["Add to parent"].tap()
        XCTAssertEqual(mealFoods.count, originalMealFoodCount + 1)
        XCTAssertTrue(app.buttons["meal-detail-save"].waitForExistence(timeout: 3))
        visibleButton("custom-food-back").tap()
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertEqual(loggedList.value as? String, originalOrder)
        meal.tap()
        XCTAssertTrue(app.buttons["meal-detail-save"].waitForExistence(timeout: 3))
        for _ in 0..<5 where !app.buttons["meal-detail-add-food"].isHittable { scrollCustomizationBody() }
        XCTAssertTrue(app.buttons["meal-detail-add-food"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Sandwich'" )).firstMatch.exists,
            "Leaving the parent meal without saving should discard the newly added food.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Logged meal — Shared composition"
        attachment.lifetime = .keepAlways; add(attachment)
        visibleButton("custom-food-back").tap()
    }

    func testLongMealScrollsBetweenPinnedSummaryAndQuantityFooter() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES"]
        app.launchEnvironment = ["CALORIE_TRACKER_CUSTOMIZATION_EVIDENCE": "long-meal-scroll"]
        app.launch()

        let body = app.scrollViews["customization-content"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        let save = app.buttons["meal-detail-save"]
        let quantity = app.textFields["meal-detail-quantity"]
        XCTAssertTrue(waitUntil(timeout: 5) { save.isHittable && quantity.isHittable })

        let mealFoods = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'meal-food-option-'"))
        let firstFood = mealFoods.firstMatch
        XCTAssertTrue(firstFood.waitForExistence(timeout: 5))
        firstFood.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))

        let lastFood = mealFoods.element(boundBy: 11)
        for _ in 0..<8 where !lastFood.isHittable { scrollCustomizationBody() }
        XCTAssertTrue(lastFood.waitForExistence(timeout: 3))
        XCTAssertTrue(lastFood.isHittable, "Vertical drags over meal food pills should reach the final ingredient.")
        let addFood = app.buttons["meal-detail-add-food"]
        let meatTracking = app.staticTexts["MEAT TRACKING"]
        for _ in 0..<5 where !addFood.isHittable { scrollCustomizationBody() }
        XCTAssertTrue(addFood.isHittable, "The Add Food control should be reachable below a long ingredient list.")
        for _ in 0..<5 where !meatTracking.isHittable { scrollCustomizationBody() }
        XCTAssertTrue(meatTracking.isHittable, "Meat tracking should be reachable below the ingredient list.")
        XCTAssertTrue(save.isHittable, "The save action stays pinned while meal contents scroll.")
        XCTAssertTrue(quantity.isHittable, "The quantity control stays pinned while meal contents scroll.")

        for _ in 0..<8 where !firstFood.isHittable { body.swipeDown() }
        XCTAssertTrue(firstFood.isHittable, "The meal scroll region should return to the first ingredient.")
        XCTAssertTrue(firstFood.isSelected)
        firstFood.tap()
        XCTAssertFalse(firstFood.isSelected)
        firstFood.tap()
        XCTAssertTrue(firstFood.isSelected)
        XCTAssertTrue(save.isHittable)

        app.terminate()
        app.launchEnvironment = ["CALORIE_TRACKER_CUSTOMIZATION_EVIDENCE": "short-meal-scroll"]
        app.launch()
        XCTAssertTrue(app.scrollViews["customization-content"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["meal-detail-add-food"].isHittable,
            "The short meal form should fit without requiring a scroll.")
        XCTAssertTrue(app.buttons["meal-detail-save"].isHittable)
        XCTAssertTrue(app.textFields["meal-detail-quantity"].isHittable)
    }

    func testMixedCatalogCustomizationAndScreenshotMatrix() {
        let arguments = ["-onboarding.focus.v1.completed", "YES", "-foodSource.enabled.chaseFood", "YES",
            "-foodSource.enabled.usda", "YES", "-foodSource.enabled.off", "YES", "-AppleInterfaceStyle", "Light"]
        func launch(_ review: String? = nil) {
            app.terminate(); app.launchArguments = arguments
            app.launchEnvironment = ["CALORIE_TRACKER_UNIFIED_FIXTURE": "1", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
            if let review { app.launchEnvironment["CALORIE_TRACKER_CUSTOMIZATION_EVIDENCE"] = review }
            app.launch()
            if review == nil { XCTAssertTrue(app.buttons["Log food"].waitForExistence(timeout: 10)) }
        }
        func capture(_ name: String) {
            XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let screenshot = app.screenshot()
            if ["usda-portioned-log", "off-packaged-log", "yum-chase-configured-log", "saved-meal-log"].contains(name) {
                let directory = URL(fileURLWithPath: "/tmp/task196-ui-evidence", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
            }
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        func open(_ query: String, id: String) {
            let launchButton = app.buttons["Log food"]
            launchButton.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            if !app.textFields["Search foods"].firstMatch.waitForExistence(timeout: 3) {
                launchButton.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            }
            let search = visibleTextField("Search foods")
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(query)
            let row = app.buttons[id]
            for _ in 0..<6 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
            // Badge/name and row space belong to the same explicit primary button.
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
            let actionTitle = id.hasPrefix("customize-meal-") ? "Log Meal" : "Log Food"
            XCTAssertTrue(app.buttons[actionTitle].waitForExistence(timeout: 5))
        }
        let foods = [
            ("plum", "customize-food-usda:2709265", "usda-portioned-log"),
            ("rice white cooked glutinous", "customize-food-usda:2708422", "usda-weight-log"),
            ("organic greek yogurt plain", "customize-food-off:0096619483556", "off-packaged-log"),
            ("sandwich", "customize-food-chaseFood:food_sandwich", "yum-chase-configured-log"),
            ("Chase's overnight oats", "customize-food-custom:task196-oats", "custom-food-log")]
        for (query, id, filename) in foods {
            launch(); open(query, id: id)
            XCTAssertFalse(app.buttons["customization-edit-title"].exists, "The title should use Rename in the actions menu")
            if filename == "yum-chase-configured-log" {
                XCTAssertEqual(app.buttons["custom-food-unit-picker"].value as? String, "grams",
                    "Search customization should start with the same remembered unit as its result row.")
                XCTAssertEqual(app.textFields["custom-food-quantity-value"].value as? String, "275")
            }
            if filename == "usda-weight-log" {
                visibleButton("custom-food-unit-picker").tap(); app.buttons["grams"].tap()
            }
            if filename == "off-packaged-log" {
                visibleButton("custom-food-unit-picker").tap(); app.buttons["0.667 cup (170 g)"].tap()
                let quantity = app.textFields["custom-food-quantity-value"]
                quantity.tap(); quantity.typeText("1"); visibleButton("Done").tap()
            }
            if filename == "custom-food-log" {
                visibleButton("custom-food-unit-picker").tap(); app.buttons["jar"].tap()
                let quantity = app.textFields["custom-food-quantity-value"]
                quantity.tap(); quantity.typeText("1"); visibleButton("Done").tap()
            }
            if filename == "yum-chase-configured-log" {
                visibleButton("custom-food-add-ingredient").tap()
                let search = visibleTextField("Search foods")
                XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("plum")
                app.buttons["customize-food-usda:2709265"].tap()
                XCTAssertTrue(app.buttons["Add to parent"].waitForExistence(timeout: 3)); capture("yum-chase-configured-child")
                app.buttons["Add to parent"].tap()
                XCTAssertTrue(app.buttons["Log Food"].waitForExistence(timeout: 5))
                for _ in 0..<8 where !app.staticTexts["FILLING"].isHittable {
                    app.scrollViews["customization-content"].swipeDown()
                }
            }
            capture(filename)
            if filename == "usda-portioned-log" {
                visibleButton("custom-food-unit-picker").tap(); capture("usda-unit-menu")
                app.buttons["grams"].tap()
                XCTAssertEqual(visibleCaloriesLabel(), "Calories 35 kcal")
            }
            if filename == "yum-chase-configured-log" {
                for _ in 0..<8 where !app.buttons["meal-component-edit-2709265"].isHittable { scrollCustomizationBody() }
                capture(filename + "-scrolled")
            }
        }
        launch(); open("Yogurt, fruit and oats", id: "customize-meal-19600000-0000-4000-8000-000000000001")
        XCTAssertFalse(app.buttons["customization-edit-title"].exists, "The title should use Rename in the actions menu")
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'meal-food-option-'" )).count, 0)
        capture("saved-meal-log"); scrollCustomizationBody(); capture("saved-meal-log-scrolled")
        for route in ["imported-meal-review", "photo-meal-review"] {
            launch(route); capture(route)
            let importedFood = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'meal-food-option-'")).firstMatch
            XCTAssertTrue(importedFood.waitForExistence(timeout: 3))
            XCTAssertTrue(importedFood.isSelected)
            importedFood.tap()
            XCTAssertFalse(importedFood.isSelected)
            importedFood.tap()
            XCTAssertTrue(importedFood.isSelected)
            XCTAssertTrue(app.switches["Save to Saved meals"].exists)
            capture(route + "-scrolled")
        }
        for (sourceID, filename) in [("2709265", "usda-portioned-edit"), ("0096619483556", "off-packaged-edit"),
            ("food_sandwich", "yum-chase-configured-edit"), ("task196-meal", "saved-meal-edit"), ("task196-one-off", "one-off-meal-edit")] {
            launch()
            let row = app.descendants(matching: .any).matching(identifier: "diary-entry-" + sourceID).firstMatch
            for _ in 0..<5 {
                if row.isHittable && row.frame.midY < app.buttons["Log food"].frame.minY - 10 { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.6))
                    .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.3)))
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5)); capture(filename)
            if sourceID == "2709265" || sourceID == "0096619483556" {
                XCTAssertFalse(app.buttons["Rebuild with current catalog values"].exists)
                let before = visibleCaloriesLabel()
                visibleButton("custom-food-quantity-plus").tap()
                XCTAssertNotEqual(visibleCaloriesLabel(), before)
                visibleButton("custom-food-back").tap()
                row.tap(); XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5))
                XCTAssertEqual(visibleCaloriesLabel(), before, "Cancel must preserve historical nutrition")
            }
        }
    }

    func testMixedCatalogQuickAddIsIndependentFromDetail() {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES", "-foodSource.enabled.chaseFood", "YES",
            "-foodSource.enabled.usda", "YES", "-foodSource.enabled.off", "YES"]
        app.launchEnvironment = ["CALORIE_TRACKER_UNIFIED_FIXTURE": "1", "CALORIE_TRACKER_FIXTURE_RESET": "1"]
        app.launch()
        let list = app.descendants(matching: .any).matching(identifier: "logged-foods-reorder-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let before = (list.value as? String ?? "").components(separatedBy: "Plum, raw").count
        app.buttons["Log food"].tap()
        let search = visibleTextField("Search foods"); search.tap(); search.typeText("plum")
        let shortcut = app.buttons["Quick add Plum, raw"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5)); shortcut.tap()
        XCTAssertFalse(app.staticTexts["custom-food-sticky-title"].exists)
        XCTAssertTrue(search.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let after = (list.value as? String ?? "").components(separatedBy: "Plum, raw").count
        XCTAssertEqual(after, before + 1, "The sibling shortcut must create exactly one entry without opening detail")
    }

    private func scrollCustomizationBody() {
        let body = app.scrollViews["customization-content"]
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
    }

    private func visibleTextField(_ identifier: String) -> XCUIElement {
        let query = app.textFields.matching(identifier: identifier)
        _ = query.firstMatch.waitForExistence(timeout: 5)
        return query.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? query.firstMatch
    }

    private func visibleCaloriesLabel() -> String {
        let matches = app.descendants(matching: .any).matching(identifier: "custom-food-estimate-calories").allElementsBoundByIndex
        return matches.first(where: { $0.isHittable })?.label ?? ""
    }

    private func visibleButton(_ identifier: String) -> XCUIElement {
        let matches = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
        return matches.first(where: { $0.isHittable }) ?? app.buttons.matching(identifier: identifier).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func confirmCheatDay(expectedCheat: Bool, doubleTap: Bool = false) {
        let confirmation = app.buttons["cheat-day-confirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        let edge = confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        if doubleTap {
            edge.doubleTap()
        } else {
            edge.tap()
        }
        let label = expectedCheat ? "Undo cheat day" : "Mark cheat day"
        let changed = app.buttons[label].waitForExistence(timeout: 3)
        if !changed {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Unresponsive cheat confirmation"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print(app.debugDescription)
        }
        XCTAssertTrue(changed)
        XCTAssertFalse(confirmation.exists, "The confirmation must dismiss and allow another action")
        XCTAssertTrue(app.buttons["cheat-day-toolbar"].isHittable)
    }

    private func launchCheatDayFixture(reset: Bool) {
        app.launchArguments = ["-onboarding.focus.v1.completed", "YES"]
        app.launchEnvironment = [
            "CALORIE_TRACKER_FIXTURE": "device",
            "CALORIE_TRACKER_FIXTURE_RESET": reset ? "1" : "0",
            // Default simulator demos reset on every launch; explicitly reuse this fixture.
            "CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE": "1"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["cheat-day-toolbar"].waitForExistence(timeout: 5))
    }

    private func assertDiaryLayout(firstEntrySourceID: String) {
        let heading = app.staticTexts["logged-heading-label"]
        let firstEntry = app.descendants(matching: .any)
            .matching(identifier: "diary-entry-\(firstEntrySourceID)")
            .firstMatch
        let actions = app.descendants(matching: .any)
            .matching(identifier: "diary-log-food-actions")
            .firstMatch

        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 3))
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            firstEntry.frame.minY,
            heading.frame.maxY - 1,
            "The first diary row overlaps the Logged heading."
        )
        XCTAssertLessThanOrEqual(
            app.frame.maxY - actions.frame.maxY,
            70,
            "The persistent logging controls are not anchored to the bottom safe area."
        )
    }
}
