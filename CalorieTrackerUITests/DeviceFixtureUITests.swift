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
