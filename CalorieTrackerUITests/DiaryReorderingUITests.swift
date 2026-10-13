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
        XCTAssertTrue(app.navigationBars["Customize Sandwich"].waitForExistence(timeout: 5))
        XCTAssertTrue(hasAccessibilityLabel(containing: "Turkey"))
        attachScreenshot(named: "Chase Food Sandwich Customization")
        openPicker(matching: "Filling")
        let hamOption = app.buttons["Ham"]
        XCTAssertTrue(hamOption.waitForExistence(timeout: 5))
        hamOption.tap()
        openPicker(matching: "Bread")
        let wheatBreadOption = app.buttons["Whole wheat bread"]
        XCTAssertTrue(wheatBreadOption.waitForExistence(timeout: 5))
        wheatBreadOption.tap()
        openPicker(matching: "Cheese")
        let cheddarOption = app.buttons["Cheddar cheese"]
        XCTAssertTrue(cheddarOption.waitForExistence(timeout: 5))
        cheddarOption.tap()
        attachScreenshot(named: "Chase Food Sandwich with Cheese")
        app.swipeUp()
        attachScreenshot(named: "Chase Food Sandwich Spreads and Cheese")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceSearchQuery("protein shake", in: searchField)
        let shakeCustomize = app.buttons["Customize Protein shake"]
        XCTAssertTrue(shakeCustomize.waitForExistence(timeout: 10))
        shakeCustomize.tap()
        XCTAssertTrue(app.navigationBars["Customize Protein shake"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Chase Food Protein Shake Customization")
        openPicker(matching: "Protein powder")
        let proteinPowderOption = app.buttons["Protein powder"]
        XCTAssertTrue(proteinPowderOption.waitForExistence(timeout: 5))
        proteinPowderOption.tap()
        openPicker(matching: "Liquid")
        XCTAssertTrue(app.buttons["Almond milk"].waitForExistence(timeout: 5))
        app.buttons["Almond milk"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceSearchQuery("protein shake", in: searchField)
        let customizeAgain = app.buttons["Customize Protein shake"]
        XCTAssertTrue(customizeAgain.waitForExistence(timeout: 10))
        customizeAgain.tap()
        XCTAssertTrue(app.navigationBars["Customize Protein shake"].waitForExistence(timeout: 5))
        app.swipeUp()
        attachScreenshot(named: "Chase Food Protein Shake Add-ons")
    }

    func testChaseFoodConceptScreensBreakfast() {
        captureChaseFoodConceptScreens([
            ("omelet", "Omelet"), ("toast", "Toast"), ("cereal", "Cereal"),
            ("coffee", "Coffee"), ("banana", "Banana"), ("yogurt", "Yogurt")
        ])
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
            customize.tap()
            XCTAssertTrue(app.navigationBars["Customize \(title)"].waitForExistence(timeout: 5))
            attachScreenshot(named: "Chase Food Concept - \(title)")
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

    private func openPicker(matching value: String) {
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Picker for \(value) was not found.")
        picker.tap()
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
