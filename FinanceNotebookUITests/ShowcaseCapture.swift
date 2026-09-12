import XCTest

/// Captures App Store screenshots from the fictional showcase dataset.
/// Not a behavioural test: it exists so the marketing screenshots come from a
/// real build rather than a mockup, and so they can be regenerated on demand.
final class ShowcaseCapture: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeedShowcase"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 30),
                      "The showcase month did not load")
        shot(app, "01-home")

        // Anchored on a control the screen always shows rather than on a
        // particular row: the lists render lazily, so which records are on
        // screen depends on where the scroll happens to be.
        app.tabBars.buttons["Transactions"].tap()
        XCTAssertTrue(app.buttons["addExpenseButton"].waitForExistence(timeout: 15),
                      "Transactions did not load")
        shot(app, "02-transactions")

        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.buttons["addCategoryButton"].waitForExistence(timeout: 15),
                      "Plan did not load")
        shot(app, "03-plan")

        app.tabBars.buttons["Review"].tap()
        let report = app.buttons["viewMonthlyReportLink"]
        XCTAssertTrue(report.waitForExistence(timeout: 15), "Review did not load")
        shot(app, "04-review")

        report.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15),
                      "The monthly report did not open")
        shot(app, "05-report")

        app.tabBars.buttons["Home"].tap()
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(identifier: "settingsView").firstMatch
                        .waitForExistence(timeout: 15),
                      "Settings did not open")
        shot(app, "06-settings")
    }
}
