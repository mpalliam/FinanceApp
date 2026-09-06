import XCTest

/// Opening a report, switching its depth, and exporting it — with real taps.
final class ReportFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeedMonth"] + extraArguments
        app.launch()
        return app
    }

    private func openTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "\(name) tab never appeared")
        tab.tap()
    }

    /// List rows render lazily, so anything below the fold is absent from the
    /// hierarchy until it has been scrolled to.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication,
                          _ message: String, line: UInt = #line) {
        var attempts = 0
        while !element.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists, message, line: line)
    }

    private func openReport(_ app: XCUIApplication) {
        openTab("Review", in: app)
        let link = app.buttons["viewMonthlyReportLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "The report link was missing")
        link.tap()
        XCTAssertTrue(app.buttons["reportLevelPicker"].firstMatch.waitForExistence(timeout: 25)
                      || app.segmentedControls.firstMatch.waitForExistence(timeout: 10),
                      "The report did not open")
    }

    private func selectLevel(_ name: String, in app: XCUIApplication) {
        let button = app.segmentedControls.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "\(name) was not offered")
        button.tap()
    }

    /// Present right now, without scrolling. Used for the negative checks,
    /// where scrolling would defeat the point.
    private func exists(_ identifier: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
    }

    /// Present somewhere in the report, scrolling to find it.
    private func findsSection(_ identifier: String, in app: XCUIApplication) -> Bool {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        var attempts = 0
        while !element.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        return element.exists
    }

    private func findsText(_ text: String, in app: XCUIApplication) -> Bool {
        let element = app.staticTexts[text]
        var attempts = 0
        while !element.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        return element.exists
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<12 { app.swipeDown() }
    }

    // MARK: - Opening

    func testOpeningTheMonthlyReport() {
        let app = launch(["-uiTestSeedExpense"])
        openReport(app)

        XCTAssertTrue(app.staticTexts["September 2026"].exists,
                      "The report did not name the month")
        XCTAssertTrue(app.staticTexts["In Progress"].exists,
                      "An open month should say it is still in progress")
        XCTAssertTrue(exists("reportFinancialSummary", in: app),
                      "The financial summary was missing")

        // Seeded month: 2,400 starting, 1,000 protected, 14.72 spent.
        // Found by label, not identifier: an identifier on a Section overrides
        // the ones on the rows inside it, so every row in the summary reports
        // "reportFinancialSummary". The trailing comma picks the combined row
        // ("Safe to Spend, $1,385.28") over the bare label beside it.
        let safeToSpend = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Safe to Spend, ")).firstMatch
        var attempts = 0
        while !safeToSpend.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(safeToSpend.exists, "Safe to Spend was missing from the report")
        XCTAssertTrue(safeToSpend.label.contains("1,385.28"),
                      "Safe to Spend wrong on the report — got \"\(safeToSpend.label)\"")
    }

    // MARK: - Detail levels

    func testSwitchingDetailLevelsShowsAndHidesSections() {
        let app = launch(["-uiTestSeedExpense", "-uiTestSeedMoneyAdded"])
        openReport(app)

        // Summary: numbers and categories only.
        selectLevel("Summary", in: app)
        XCTAssertTrue(findsSection("reportFinancialSummary", in: app))
        XCTAssertTrue(findsSection("reportCategorySummary", in: app))
        // Scroll to the end, then check the deeper sections are nowhere in it.
        _ = findsSection("exportPDFButton", in: app)
        XCTAssertFalse(exists("reportMoneyAdded", in: app),
                       "Summary should not show Money Added")
        XCTAssertFalse(exists("reportExpenseLedger", in: app),
                       "Summary should not show the ledger")
        XCTAssertFalse(exists("reportWeeklyReviews", in: app))
        XCTAssertFalse(exists("reportMonthlyReflection", in: app))
        scrollToTop(app)

        // Standard: adds what came in, and the reflection.
        selectLevel("Standard", in: app)
        scrollTo(app.descendants(matching: .any)
                    .matching(identifier: "reportMoneyAdded").firstMatch,
                 in: app, "Standard did not show Money Added")
        XCTAssertTrue(findsSection("reportMonthlyReflection", in: app),
                      "Standard did not show the reflection")
        // Scrolled through the whole report and the ledger was never there.
        XCTAssertFalse(exists("reportExpenseLedger", in: app),
                       "Standard must not carry the whole ledger")
        scrollToTop(app)

        // Full: everything.
        selectLevel("Full", in: app)
        scrollTo(app.descendants(matching: .any)
                    .matching(identifier: "reportExpenseLedger").firstMatch,
                 in: app, "Full did not show the expense ledger")
        scrollTo(app.descendants(matching: .any)
                    .matching(identifier: "reportWeeklyReviews").firstMatch,
                 in: app, "Full did not show the weekly check-ins")
    }

    // MARK: - Export

    func testExportingAFullReportOpensTheShareSheet() {
        let app = launch(["-uiTestSeedExpense", "-uiTestSeedMoneyAdded"])
        openReport(app)
        selectLevel("Full", in: app)

        let export = app.buttons["exportPDFButton"]
        scrollTo(export, in: app, "Export PDF was not reachable")
        export.tap()

        // The system share sheet, with the generated file named after the month.
        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        let namedFile = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'Finance-Notebook'")).firstMatch
        let appeared = shareSheet.waitForExistence(timeout: 15)
            || namedFile.waitForExistence(timeout: 5)
        XCTAssertTrue(appeared, "The share sheet did not appear")

        // Dismiss it without sending anything anywhere.
        if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
        } else {
            app.swipeDown()
        }

        XCTAssertTrue(app.buttons["exportPDFButton"].waitForExistence(timeout: 10)
                      || app.segmentedControls.firstMatch.exists,
                      "Did not return to the report after sharing")
    }

    /// A closed month is exactly the kind worth reporting on, and exporting it
    /// must not disturb it.
    func testExportingAClosedMonthLeavesItClosed() {
        let app = launch(["-uiTestSeedExpense"])

        // Close the month through the production UI.
        openTab("Plan", in: app)
        let close = app.buttons["closeMonthButton"]
        scrollTo(close, in: app, "Close Month was not reachable")
        close.tap()
        app.buttons["confirmCloseMonthButton"].firstMatch.tap()

        openReport(app)
        XCTAssertTrue(app.staticTexts["Closed"].exists,
                      "The report did not show the month as closed")

        selectLevel("Full", in: app)
        let export = app.buttons["exportPDFButton"]
        scrollTo(export, in: app, "Export PDF was not reachable")
        export.tap()

        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        let namedFile = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'Finance-Notebook'")).firstMatch
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 15)
                      || namedFile.waitForExistence(timeout: 5),
                      "A closed month could not be exported")

        if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
        } else {
            app.swipeDown()
        }

        // Still closed, and still read-only.
        openTab("Home", in: app)
        XCTAssertTrue(findsText("This month is closed. It is read-only.", in: app),
                      "Exporting reopened the month")
        XCTAssertFalse(app.buttons["homeAddExpenseButton"].exists,
                       "The month stopped being read-only after an export")
    }
}
