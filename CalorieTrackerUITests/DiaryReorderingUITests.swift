import XCTest

final class DiaryReorderingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testLongPressDragReordersVisuallyAndPersists() {
        launchApp(resetFixture: true)

        var alpha = row("reorder-alpha")
        var beta = row("reorder-beta")
        var gamma = row("reorder-gamma")
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.waitForExistence(timeout: 5))
        XCTAssertTrue(gamma.waitForExistence(timeout: 5))
        XCTAssertLessThan(alpha.frame.minY, beta.frame.minY)
        XCTAssertLessThan(beta.frame.minY, gamma.frame.minY)

        let start = alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = gamma.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.7, thenDragTo: destination)

        XCTAssertTrue(
            waitUntil(timeout: 4) { alpha.frame.minY > gamma.frame.minY },
            "The dragged row never moved below the crossed rows."
        )
        let persistedOrder = orderValue()
        XCTAssertNotEqual(persistedOrder, "Reorder Alpha, Reorder Beta, Reorder Gamma, Reorder Delta")

        app.terminate()
        launchApp(resetFixture: false)
        alpha = row("reorder-alpha")
        beta = row("reorder-beta")
        gamma = row("reorder-gamma")
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.waitForExistence(timeout: 5))
        XCTAssertTrue(gamma.waitForExistence(timeout: 5))
        XCTAssertEqual(orderValue(), persistedOrder)
        XCTAssertGreaterThan(alpha.frame.minY, gamma.frame.minY)
    }

    func testStationaryLongPressDuplicatesLoggedFoodToday() {
        launchApp(resetFixture: true)

        let alpha = row("reorder-alpha")
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)
            .matching(identifier: "diary-entry-reorder-alpha").count, 2)

        alpha.press(forDuration: 0.6)
        let duplicateAction = app.descendants(matching: .any)
            .matching(identifier: "Duplicate Today")
            .firstMatch
        XCTAssertTrue(duplicateAction.waitForExistence(timeout: 5))
        duplicateAction.tap()

        XCTAssertTrue(waitUntil(timeout: 5) {
            app.descendants(matching: .any)
                .matching(identifier: "diary-entry-reorder-alpha").count == 4
        }, "Duplicating the row did not add a second diary entry.")
    }

    func testMultiSelectDuplicatesSelectedFoodsToday() {
        launchApp(resetFixture: true)

        let selectButton = app.buttons["Select"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 5))
        selectButton.tap()

        let alphaSelection = app.buttons["selected-diary-entry-reorder-alpha"]
        let betaSelection = app.buttons["selected-diary-entry-reorder-beta"]
        XCTAssertTrue(alphaSelection.waitForExistence(timeout: 5))
        XCTAssertTrue(betaSelection.waitForExistence(timeout: 5))
        alphaSelection.tap()
        betaSelection.tap()

        XCTAssertTrue(app.staticTexts["2 selected"].exists)
        let logTodayButton = app.buttons["Log Today"]
        XCTAssertTrue(logTodayButton.exists)
        attachScreenshot(named: "Multi-select Actions")
        logTodayButton.tap()

        XCTAssertTrue(waitUntil(timeout: 5) {
            app.descendants(matching: .any).matching(identifier: "diary-entry-reorder-alpha").count == 4
                && app.descendants(matching: .any).matching(identifier: "diary-entry-reorder-beta").count == 4
        }, "Multi-select duplication did not add both selected rows.")
    }

    func testChaseFoodSandwichAndProteinShakeCustomizationScreens() {
        app.launchArguments = [
            "--show-food-search",
            "-foodSource.enabled.chaseFood", "YES",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launch()

        let searchField = app.textFields["Search foods"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        replaceSearchQuery("sandwich", in: searchField)
        let sandwichCustomize = app.buttons["Customize Sandwich"]
        XCTAssertTrue(sandwichCustomize.waitForExistence(timeout: 10))
        sandwichCustomize.tap()
        XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(hasAccessibilityLabel(containing: "Turkey"))
        attachScreenshot(named: "Chase Food Sandwich Customization")
        app.swipeUp()
        let hamOption = app.buttons["Ham"]
        XCTAssertTrue(hamOption.waitForExistence(timeout: 5))
        hamOption.tap()
        let wheatBreadOption = app.buttons["Whole wheat"]
        for _ in 0..<8 where !wheatBreadOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(wheatBreadOption.waitForExistence(timeout: 5))
        wheatBreadOption.tap()
        let cheddar = app.buttons["Cheddar"]
        XCTAssertTrue(cheddar.waitForExistence(timeout: 5))
        cheddar.tap()
        attachScreenshot(named: "Chase Food Sandwich with Cheese")
        app.swipeUp()
        attachScreenshot(named: "Chase Food Sandwich Spreads and Cheese")
        app.buttons["custom-food-back"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceSearchQuery("protein shake", in: searchField)
        let shakeCustomize = app.buttons["Customize Protein shake"]
        XCTAssertTrue(shakeCustomize.waitForExistence(timeout: 10))
        shakeCustomize.tap()
        XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Chase Food Protein Shake Customization")
        let proteinPowderOption = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "protein powder")
        ).firstMatch
        XCTAssertTrue(proteinPowderOption.waitForExistence(timeout: 5))
        proteinPowderOption.tap()
        XCTAssertTrue(app.buttons["Almond milk"].waitForExistence(timeout: 5))
        app.buttons["Almond milk"].tap()
        app.buttons["custom-food-back"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceSearchQuery("protein shake", in: searchField)
        let customizeAgain = app.buttons["Customize Protein shake"]
        XCTAssertTrue(customizeAgain.waitForExistence(timeout: 10))
        customizeAgain.tap()
        XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 5))
        app.swipeUp()
        attachScreenshot(named: "Chase Food Protein Shake Add-ons")
    }

    func testChaseFoodConceptScreensBreakfast() {
        captureChaseFoodConceptScreens([
            ("omelet", "Omelet"), ("toast", "Toast"), ("cereal", "Cereal"),
            ("coffee", "Coffee"), ("banana", "Banana"), ("yogurt", "Yogurt")
        ])
    }

    func testChaseFoodTacoStickySummaryAndQuantityPicker() {
        app.launchArguments = [
            "--show-food-search",
            "-foodSource.enabled.chaseFood", "YES",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launch()
        let searchField = app.textFields["Search foods"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        replaceSearchQuery("taco", in: searchField)
        let customize = app.buttons["Customize Taco"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        for _ in 0..<6 where !customize.isHittable { app.swipeUp() }
        XCTAssertTrue(customize.isHittable)
        customize.tap()

        let stickyTitle = app.staticTexts["custom-food-sticky-title"]
        XCTAssertTrue(stickyTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(stickyTitle.label, "Taco")
        let backButton = app.buttons["custom-food-back"]
        XCTAssertTrue(backButton.exists)
        XCTAssertLessThan(backButton.frame.maxX, stickyTitle.frame.minX)
        XCTAssertTrue(app.otherElements["custom-food-estimate-calories"].exists)
        let unitPicker = app.buttons["custom-food-unit-picker"]
        XCTAssertTrue(unitPicker.exists)
        XCTAssertEqual(unitPicker.value as? String, "Small")
        XCTAssertTrue(app.descendants(matching: .any)["custom-food-macro-bar"].exists)
        attachScreenshot(named: "Chase Food Taco Sticky Summary and Quantity")

        let titleY = stickyTitle.frame.minY
        app.swipeUp()
        XCTAssertTrue(stickyTitle.exists)
        XCTAssertEqual(stickyTitle.frame.minY, titleY, accuracy: 1)

        unitPicker.tap()
        for choice in ["Small", "Medium", "Large", "ounces", "grams"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 3), "Missing quantity choice: \(choice).")
        }
        attachScreenshot(named: "Chase Food Taco Portion and Weight Choices")
        let gramsChoice = app.buttons["grams"]
        XCTAssertTrue(gramsChoice.waitForExistence(timeout: 5))
        gramsChoice.tap()
        let quantity = app.textFields["custom-food-quantity-value"]
        XCTAssertEqual(quantity.value as? String, "50")
        app.buttons["custom-food-quantity-plus"].tap()
        XCTAssertEqual(quantity.value as? String, "51")

        let addIngredient = app.buttons["custom-food-add-ingredient"]
        for _ in 0..<8 where !addIngredient.isHittable { app.swipeUp() }
        XCTAssertTrue(addIngredient.isHittable)
        addIngredient.tap()
        XCTAssertTrue(app.navigationBars["Add ingredient"].waitForExistence(timeout: 5))
        let ingredientSearch = app.searchFields["Search foods"]
        XCTAssertTrue(ingredientSearch.waitForExistence(timeout: 5))
        replaceSearchQuery("salsa", in: ingredientSearch)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Salsa")).firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(named: "Chase Food Ingredient Search")
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Salsa")).firstMatch.tap()
        XCTAssertTrue(addIngredient.waitForExistence(timeout: 5))
        let suggestChange = app.buttons["custom-food-show-suggestions"]
        let footerControl = app.buttons["custom-food-quantity-plus"]
        for _ in 0..<12 where suggestChange.frame.maxY > footerControl.frame.minY - 80 { app.swipeUp() }
        XCTAssertTrue(suggestChange.isHittable)
        suggestChange.tap()
        XCTAssertTrue(app.navigationBars["Suggested changes"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Chase Food Suggested Changes")
    }

    func testChaseFoodSavedVariationsInSearch() {
        app.launchArguments = [
            "--show-food-search",
            "-foodSource.enabled.chaseFood", "YES",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launch()

        let searchField = app.textFields["Search foods"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        replaceSearchQuery("cappuccino", in: searchField)
        let customize = app.buttons["Customize Cappuccino"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        customize.tap()
        XCTAssertTrue(app.staticTexts["custom-food-sticky-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["custom-food-recent-variations"].exists)
        attachScreenshot(named: "Chase Food Cappuccino Recent Variations Menu")

        app.buttons["Log Food"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceSearchQuery("cappuccino", in: searchField)
        let savedVariation = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Small, 8 fl oz")
        ).firstMatch
        XCTAssertTrue(savedVariation.waitForExistence(timeout: 10))
        XCTAssertFalse(savedVariation.label.localizedCaseInsensitiveContains("Cappuccino"))
        attachScreenshot(named: "Chase Food Cappuccino Compact Saved Variation")

        customize.tap()
        let recentVariations = app.buttons["custom-food-recent-variations"]
        XCTAssertTrue(recentVariations.waitForExistence(timeout: 5))
        recentVariations.tap()
        let recentCappuccino = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Small, 8 fl oz")
        ).firstMatch
        XCTAssertTrue(recentCappuccino.waitForExistence(timeout: 5))
        attachScreenshot(named: "Chase Food Cappuccino Recent Variations Menu Open")
    }

    func testSavedVariationQuickAddCenterCoordinateUsesTheTappedProteinShake() {
        verifySavedVariationQuickAddUsesPeanutButter(at: CGVector(dx: 0.5, dy: 0.5))
    }

    func testSavedVariationQuickAddLowerEdgeUsesTheTappedProteinShake() {
        verifySavedVariationQuickAddUsesPeanutButter(at: CGVector(dx: 0.5, dy: 0.9))
    }

    func testSavedVariationQuickAddRightSideUsesTheTappedProteinShake() {
        verifySavedVariationQuickAddUsesPeanutButter(at: CGVector(dx: 0.9, dy: 0.5))
    }

    private func verifySavedVariationQuickAddUsesPeanutButter(at point: CGVector) {
        app.launchArguments = [
            "--show-food-search",
            "-foodSource.enabled.chaseFood", "YES",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launchEnvironment = [
            "CALORIE_TRACKER_FIXTURE": "device",
            "CALORIE_TRACKER_FIXTURE_RESET": "1",
            "CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE": "1"
        ]
        app.launch()

        let searchField = app.textFields["Search foods"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        replaceSearchQuery("protein shake", in: searchField)
        let customize = app.buttons["customize-food-chaseFood:food_protein_shake"]

        // Save two variations whose visible ingredient labels distinguish the log.
        for ingredient in ["Peanut butter", "Banana"] {
            XCTAssertTrue(customize.waitForExistence(timeout: 10))
            customize.tap()
            let option = app.buttons[ingredient]
            for _ in 0..<8 where !option.isHittable { app.swipeUp() }
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            app.buttons["Log Food"].tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        }

        // Reopen search with saved variations already present, before any detail has opened.
        app.terminate()
        app.launchEnvironment["CALORIE_TRACKER_FIXTURE_RESET"] = "0"
        app.launch()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        replaceSearchQuery("protein shake", in: searchField)

        let bananaAdd = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Quick add", "Banana"
        )).firstMatch
        let peanutButterAdd = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Quick add", "Peanut butter"
        )).firstMatch
        XCTAssertTrue(bananaAdd.waitForExistence(timeout: 5))
        XCTAssertTrue(peanutButterAdd.waitForExistence(timeout: 5))
        XCTAssertLessThan(bananaAdd.frame.midY, peanutButterAdd.frame.midY)
        let bananaVariation = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Select saved variation:", "Banana"
        )).firstMatch
        let peanutButterVariation = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Select saved variation:", "Peanut butter"
        )).firstMatch
        XCTAssertTrue(bananaVariation.waitForExistence(timeout: 5))
        XCTAssertTrue(peanutButterVariation.waitForExistence(timeout: 5))

        let targetScreenshot = app.screenshot()
        let targetImage = XCTAttachment(screenshot: targetScreenshot)
        targetImage.name = "Protein shake simulator tap targets"
        targetImage.lifetime = .keepAlways
        add(targetImage)
        let image = targetScreenshot.image.cgImage!
        let targetGeometry = """
        image_pixels: \(image.width)x\(image.height)
        image_scale: \(targetScreenshot.image.scale)
        app_frame: \(app.frame)
        banana_variation_row: \(bananaVariation.frame)
        peanut_butter_variation_row: \(peanutButterVariation.frame)
        banana_quick_add: \(bananaAdd.frame)
        peanut_butter_quick_add: \(peanutButterAdd.frame)
        """
        let geometryAttachment = XCTAttachment(string: targetGeometry)
        geometryAttachment.name = "Protein shake simulator hit-area geometry"
        geometryAttachment.lifetime = .keepAlways
        add(geometryAttachment)

        // Tap the rendered button using a coordinate event, not its AX action.
        // The current picker should keep its original order while the next visit
        // should reflect the variation that was most recently used.
        peanutButterAdd.coordinate(withNormalizedOffset: point).tap()
        let currentPeanutButterVariation = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Select saved variation:", "Peanut butter"
        )).firstMatch
        let currentBananaVariation = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Select saved variation:", "Banana"
        )).firstMatch
        XCTAssertTrue(currentPeanutButterVariation.waitForExistence(timeout: 5))
        XCTAssertTrue(currentBananaVariation.exists)
        XCTAssertLessThan(currentBananaVariation.frame.midY, currentPeanutButterVariation.frame.midY)
        app.buttons["Done"].tap()
        let loggedPeanutButter = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Contains Protein powder, Almond milk, Peanut butter"
        )).firstMatch
        XCTAssertTrue(loggedPeanutButter.waitForExistence(timeout: 5))

        app.buttons["Log food"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceSearchQuery("protein shake", in: searchField)
        let nextPeanutButterVariation = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Select saved variation:", "Peanut butter"
        )).firstMatch
        let nextBananaVariation = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Select saved variation:", "Banana"
        )).firstMatch
        XCTAssertTrue(nextPeanutButterVariation.waitForExistence(timeout: 5))
        XCTAssertTrue(nextBananaVariation.exists)
        XCTAssertLessThan(nextPeanutButterVariation.frame.midY, nextBananaVariation.frame.midY)
    }

    func testChaseFoodConceptScreensMeals() {
        captureChaseFoodConceptScreens([
            ("burger", "Burger"), ("pizza", "Pizza"), ("taco", "Taco"),
            ("pasta with sauce", "Pasta with sauce"), ("sandwich", "Sandwich"),
            ("lasagna", "Lasagna")
        ])
    }

    func testChaseFoodConceptScreensPersonalAndSalads() {
        captureChaseFoodConceptScreens([
            ("cappuccino", "Cappuccino"), ("protein shake", "Protein shake"),
            ("caesar salad", "Caesar salad"), ("salad", "Salad"),
            ("potato salad", "Potato salad"), ("pancake", "Pancake")
        ])
    }

    func testChaseFoodConceptScreensDinner() {
        captureChaseFoodConceptScreens([
            ("chili", "Chili"), ("beef stew", "Beef stew"),
            ("chicken parmesan", "Chicken Parmesan"),
            ("chicken piccata", "Chicken piccata"), ("orange chicken", "Orange chicken"),
            ("roast turkey", "Roast turkey"), ("cheesecake", "Cheesecake")
        ])
    }

    private func captureChaseFoodConceptScreens(_ concepts: [(String, String)]) {
        app.launchArguments = [
            "--show-food-search",
            "-foodSource.enabled.chaseFood", "YES",
            "-onboarding.focus.v1.completed", "YES"
        ]
        app.launch()
        let searchField = app.textFields["Search foods"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        for (query, title) in concepts {
            replaceSearchQuery(query, in: searchField)
            let customize = app.buttons["Customize \(title)"]
            XCTAssertTrue(customize.waitForExistence(timeout: 10), "No Chase Food result for \(title).")
            for _ in 0..<6 where !customize.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(customize.isHittable, "Customize action for \(title) is not visible.")
            customize.tap()
            let stickyTitle = app.staticTexts["custom-food-sticky-title"]
            XCTAssertTrue(stickyTitle.waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["custom-food-macro-bar"].exists)
            XCTAssertTrue(app.buttons["custom-food-unit-picker"].exists)
            let originalTitleY = stickyTitle.frame.minY
            attachScreenshot(named: "Chase Food Concept - \(title)")
            app.swipeUp()
            XCTAssertTrue(stickyTitle.exists, "The food title should stay visible when scrolling.")
            XCTAssertEqual(stickyTitle.frame.minY, originalTitleY, accuracy: 1)
            app.buttons["Cancel"].tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        }
    }

    private func replaceSearchQuery(_ query: String, in field: XCUIElement) {
        field.tap()
        let clear = app.buttons["Clear"]
        if clear.exists { clear.tap() }
        field.tap()
        field.typeText(query)
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.exists { searchKey.tap() }
    }

    private func hasAccessibilityLabel(containing value: String) -> Bool {
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", value))
            .firstMatch
        return match.waitForExistence(timeout: 5)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchApp(resetFixture: Bool) {
        app.launchArguments = ["--show-scrolled-diary", "-onboarding.focus.v1.completed", "YES"]
        app.launchEnvironment = [
            "CALORIE_TRACKER_UI_TEST_FIXTURE": "reorder",
            "CALORIE_TRACKER_UI_TEST_RESET": resetFixture ? "1" : "0"
        ]
        app.launch()
    }

    private func row(_ sourceID: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "diary-entry-\(sourceID)")
            .firstMatch
    }

    private func orderValue() -> String {
        let list = app.descendants(matching: .any)
            .matching(identifier: "logged-foods-reorder-list")
            .firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        return list.value as? String ?? ""
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
