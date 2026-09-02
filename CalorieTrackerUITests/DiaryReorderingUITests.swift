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
