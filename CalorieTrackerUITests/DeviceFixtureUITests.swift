import XCTest

final class DeviceFixtureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testDeviceFixtureShowsRelativeDays() {
        app.launchArguments = ["--show-scrolled-diary"]
        app.launchEnvironment = [
            "CALORIE_TRACKER_FIXTURE": "device",
            "CALORIE_TRACKER_FIXTURE_RESET": "1"
        ]
        app.launch()

        let loggedFoods = app.descendants(matching: .any)
            .matching(identifier: "logged-foods-reorder-list")
            .firstMatch
        XCTAssertTrue(loggedFoods.waitForExistence(timeout: 5))
        XCTAssertTrue((loggedFoods.value as? String ?? "").contains("Cappuccino"))
        assertDiaryLayout(firstEntrySourceID: "saved-meal-B4176616-B011-437F-B1B6-1C8CF89B6162")

        app.buttons["Log food"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(loggedFoods.waitForExistence(timeout: 3))
        assertDiaryLayout(firstEntrySourceID: "saved-meal-B4176616-B011-437F-B1B6-1C8CF89B6162")

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
        XCTAssertTrue(app.staticTexts["Nothing logged"].waitForExistence(timeout: 3))
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
