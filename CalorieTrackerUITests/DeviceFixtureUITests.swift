import XCTest

final class DeviceFixtureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
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
