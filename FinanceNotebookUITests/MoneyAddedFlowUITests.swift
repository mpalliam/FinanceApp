import XCTest

/// The Money Added journey with real taps, and the month's figures checked
/// after each change so the numbers are proven to follow the records.
final class MoneyAddedFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(seedMoney: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeedMonth"]
        if seedMoney {
            app.launchArguments.append("-uiTestSeedMoneyAdded")
        }
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App did not actually terminate")
        app.launchArguments = []
        app.launch()
    }

    private func openPlan(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Plan tab never appeared")
        tab.tap()
    }

    /// The Plan screen is taller than one screen, so anything below the fold
    /// has to be scrolled into reach before it can be tapped.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication,
                          _ message: String, line: UInt = #line) {
        var attempts = 0
        while !element.isHittable && attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, message, line: line)
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<8 { app.swipeDown() }
    }

    private func summaryLabel(_ identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        guard element.waitForExistence(timeout: 10) else { return "" }
        return element.label
    }

    private func assertSummary(
        _ identifier: String, contains value: String,
        in app: XCUIApplication, _ message: String, line: UInt = #line
    ) {
        let label = summaryLabel(identifier, in: app)
        XCTAssertTrue(label.contains(value), "\(message) — got \"\(label)\"", line: line)
    }

    private func clearAndType(_ text: String, into field: XCUIElement) {
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            )
        }
        field.typeText(text)
    }

    /// A single swipe does not always register in a List, so retry rather than
    /// leave a race in the suite.
    private func revealSwipeDelete(on row: XCUIElement, in app: XCUIApplication,
                                   line: UInt = #line) {
        for _ in 0..<4 {
            row.swipeLeft()
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 3), delete.isHittable {
                delete.tap()
                return
            }
        }
        XCTFail("The swipe never revealed a Delete action", line: line)
    }

    private func moneyRow(_ source: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "moneyAdded-\(source)").firstMatch
    }

    // MARK: - Add

    /// Creates the entry by typing, not by seeding, then checks every figure.
    func testAddMoneyUpdatesTheMonthAndSurvivesRelaunch() {
        let app = launch()
        openPlan(app)

        // Seeded month: starting 2,400, protected 1,000, nothing added or spent.
        assertSummary("summaryMoneyAdded", contains: "0", in: app,
                      "Money Added should start at zero")
        assertSummary("summaryTotalMoney", contains: "2,400", in: app, "Total Money wrong")
        assertSummary("summarySafeToSpend", contains: "1,400", in: app, "Safe to Spend wrong")

        // --- Add $100 Refund by hand ----------------------------------------
        // List cells render lazily, so the section has to be scrolled into view
        // before anything inside it is in the hierarchy at all.
        let addButton = app.buttons["addMoneyButton"]
        scrollTo(addButton, in: app, "Add Money button never became reachable")

        XCTAssertTrue(app.staticTexts["No Money Added"].exists,
                      "Empty state missing before any entry exists")

        addButton.tap()

        let amount = app.textFields["moneyAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Add Money form did not open")
        amount.tap()
        amount.typeText("100")

        let source = app.textFields["moneySourceField"]
        source.tap()
        source.typeText("Refund")

        app.buttons["saveMoneyButton"].tap()

        // --- The entry appears, signed --------------------------------------
        let row = moneyRow("Refund", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The entry did not appear")
        XCTAssertTrue(row.label.contains("100"), "Row is missing the amount: \(row.label)")
        XCTAssertTrue(row.label.contains("+"), "Row should read as an addition: \(row.label)")
        XCTAssertFalse(row.label.contains("$+"), "Malformed signed currency: \(row.label)")

        // --- The month's figures moved ---------------------------------------
        scrollToTop(app)
        assertSummary("summaryMoneyAdded", contains: "100", in: app,
                      "Money Added did not include the new entry")
        assertSummary("summaryTotalMoney", contains: "2,500", in: app,
                      "Total Money did not increase")
        assertSummary("summaryMoneyRemaining", contains: "2,500", in: app,
                      "Money Remaining did not increase")
        assertSummary("summarySafeToSpend", contains: "1,500", in: app,
                      "Safe to Spend did not increase")

        // --- And all of it survives being killed ------------------------------
        relaunch(app)
        openPlan(app)
        scrollTo(moneyRow("Refund", in: app), in: app,
                 "The entry did not survive relaunch")
        XCTAssertTrue(moneyRow("Refund", in: app).label.contains("100"),
                      "The amount did not survive relaunch")

        scrollToTop(app)
        assertSummary("summaryMoneyAdded", contains: "100", in: app,
                      "Money Added did not persist")
        assertSummary("summarySafeToSpend", contains: "1,500", in: app,
                      "Safe to Spend did not persist")
    }

    // MARK: - Edit

    func testEditMoneyUpdatesTheMonthAndSurvivesRelaunch() {
        let app = launch(seedMoney: true)
        openPlan(app)

        assertSummary("summaryMoneyAdded", contains: "100", in: app, "Seeded entry missing")
        assertSummary("summarySafeToSpend", contains: "1,500", in: app,
                      "Safe to Spend wrong before editing")

        let row = moneyRow("Refund", in: app)
        scrollTo(row, in: app, "Seeded entry never became reachable")
        row.tap()

        XCTAssertTrue(app.buttons["editMoneyButton"].waitForExistence(timeout: 10),
                      "Money Added detail did not open")
        app.buttons["editMoneyButton"].tap()

        let amount = app.textFields["moneyAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Edit form did not open")
        clearAndType("150", into: amount)
        app.buttons["saveMoneyButton"].tap()

        // Back on the detail screen, then back to Plan.
        XCTAssertTrue(app.buttons["editMoneyButton"].waitForExistence(timeout: 10),
                      "Did not return to the detail screen after saving")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        scrollToTop(app)
        assertSummary("summaryMoneyAdded", contains: "150", in: app,
                      "Money Added did not follow the edit")
        assertSummary("summaryTotalMoney", contains: "2,550", in: app,
                      "Total Money did not follow the edit")
        assertSummary("summarySafeToSpend", contains: "1,550", in: app,
                      "Safe to Spend did not follow the edit")

        relaunch(app)
        openPlan(app)
        assertSummary("summaryMoneyAdded", contains: "150", in: app,
                      "The edit did not persist")
    }

    // MARK: - Delete

    func testDeleteMoneyReducesTheMonthAndStaysDeleted() {
        let app = launch(seedMoney: true)
        openPlan(app)

        assertSummary("summarySafeToSpend", contains: "1,500", in: app,
                      "Safe to Spend wrong before deleting")

        let row = moneyRow("Refund", in: app)
        scrollTo(row, in: app, "Seeded entry never became reachable")
        row.tap()

        XCTAssertTrue(app.buttons["deleteMoneyButton"].waitForExistence(timeout: 10),
                      "Money Added detail did not open")
        app.buttons["deleteMoneyButton"].tap()

        // Money must never be removed on a single tap.
        let confirm = app.buttons["confirmDeleteMoneyButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                      "Delete did not ask for confirmation")
        confirm.tap()

        let gone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: moneyRow("Refund", in: app)
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed,
                       "The entry was not removed from the list")

        scrollToTop(app)
        assertSummary("summaryMoneyAdded", contains: "0", in: app,
                      "Money Added did not return to zero")
        assertSummary("summaryTotalMoney", contains: "2,400", in: app,
                      "Total Money did not decrease")
        assertSummary("summarySafeToSpend", contains: "1,400", in: app,
                      "Safe to Spend did not decrease")

        relaunch(app)
        openPlan(app)
        // Scroll the section into view first: an off-screen row is absent from
        // the hierarchy anyway, so asserting that alone would prove nothing.
        scrollTo(app.buttons["addMoneyButton"], in: app,
                 "Money Added section never became reachable")
        XCTAssertTrue(app.staticTexts["No Money Added"].exists,
                      "The empty state did not come back after deleting")
        XCTAssertFalse(moneyRow("Refund", in: app).exists,
                       "The deleted entry came back after relaunch")

        scrollToTop(app)
        assertSummary("summarySafeToSpend", contains: "1,400", in: app,
                      "Safe to Spend wrong after relaunch")
    }

    /// A swipe must not destroy a record on its own.
    func testSwipeToDeleteAsksForConfirmationFirst() {
        let app = launch(seedMoney: true)
        openPlan(app)

        let row = moneyRow("Refund", in: app)
        scrollTo(row, in: app, "Seeded entry never became reachable")
        revealSwipeDelete(on: row, in: app)

        XCTAssertTrue(app.buttons["confirmDeleteMoneyFromListButton"].firstMatch
                        .waitForExistence(timeout: 10),
                      "Swipe-to-delete removed the entry without confirmation")

        // The dialog is presented as a popover here, where the cancel button is
        // not drawn: dismissing means tapping outside it.
        let cancel = app.buttons["cancelDeleteMoneyFromListButton"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }

        XCTAssertTrue(moneyRow("Refund", in: app).waitForExistence(timeout: 10),
                      "Cancelling the confirmation still deleted the entry")
    }

    /// Money Added must not disturb spending.
    func testMoneyAddedDoesNotAffectExpenses() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeedMonth",
                               "-uiTestSeedExpense", "-uiTestSeedMoneyAdded"]
        app.launch()

        openPlan(app)
        // Starting 2,400 + added 100 - spent 14.72 - protected 1,000.
        assertSummary("summarySpent", contains: "14.72", in: app,
                      "Money Added changed what was spent")
        assertSummary("summaryTotalMoney", contains: "2,500", in: app, "Total Money wrong")
        assertSummary("summarySafeToSpend", contains: "1,485.28", in: app,
                      "Safe to Spend did not combine spending and money added")

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertTrue(app.buttons["expense-Chipotle"].waitForExistence(timeout: 10),
                      "The expense disappeared once Money Added existed")
    }
}
