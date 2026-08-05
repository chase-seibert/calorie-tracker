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

        let yesterday = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Yesterday'")
        ).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 3))
        yesterday.tap()
        XCTAssertTrue((loggedFoods.value as? String ?? "").contains("Chili, no rice"))

        let tomorrow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Tomorrow'")
        ).firstMatch
        tomorrow.tap()
        XCTAssertTrue(app.staticTexts["Nothing logged"].waitForExistence(timeout: 3))
    }
}
