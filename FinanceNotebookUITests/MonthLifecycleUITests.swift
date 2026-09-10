import XCTest

/// The month lifecycle driven with real taps: first setup, Home reacting to
/// the ledger, switching months, rolling over, and closing.
final class MonthLifecycleUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"] + extraArguments
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        // terminate() is a hard kill. Under full-suite load it can land before
        // SQLite has finished committing the last save, so let the app settle
        // rather than racing it -- the data is on disk either way, but the test
        // must not depend on winning that race.
        _ = app.wait(for: .runningForeground, timeout: 5)
        Thread.sleep(forTimeInterval: 1.5)

        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App did not actually terminate")
        app.launchArguments = []
        app.launch()
    }

    private func openTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "\(name) tab never appeared")
        tab.tap()
    }

    private func label(_ identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        guard element.waitForExistence(timeout: 10) else { return "" }
        return element.label
    }

    private func assertLabel(
        _ identifier: String, contains value: String,
        in app: XCUIApplication, _ message: String, line: UInt = #line
    ) {
        let text = label(identifier, in: app)
        XCTAssertTrue(text.contains(value), "\(message) — got \"\(text)\"", line: line)
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

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication,
                          _ message: String, line: UInt = #line) {
        var attempts = 0
        while !element.isHittable && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, message, line: line)
    }

    /// For elements that are not tappable -- a Label is never `isHittable`, so
    /// the tap-oriented helper above would spin forever on one.
    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication,
                                   _ message: String, line: UInt = #line) {
        var attempts = 0
        while !element.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists, message, line: line)
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<10 { app.swipeDown() }
    }

    /// Adds an expense through Home's quick action.
    private func addExpenseFromHome(_ amount: String, _ merchant: String,
                                    in app: XCUIApplication) {
        openTab("Home", in: app)
        scrollTo(app.buttons["homeAddExpenseButton"], in: app, "Add Expense not reachable")
        app.buttons["homeAddExpenseButton"].tap()

        let amountField = app.textFields["amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 10), "Add Expense did not open")
        amountField.tap(); amountField.typeText(amount)
        let merchantField = app.textFields["merchantField"]
        merchantField.tap(); merchantField.typeText(merchant)
        app.buttons["saveExpenseButton"].tap()
    }

    // MARK: - First month

    func testCreateFirstMonthFromAnEmptyStore() {
        let app = launch()

        XCTAssertTrue(app.staticTexts["No Month Set Up"].waitForExistence(timeout: 20),
                      "The empty store did not offer to start a month")
        app.buttons["startAMonthButton"].tap()

        let starting = app.textFields["startingMoneyField"]
        XCTAssertTrue(starting.waitForExistence(timeout: 10), "Create Month did not open")
        starting.tap(); starting.typeText("2400")

        let protected = app.textFields["protectedMoneyField"]
        protected.tap(); protected.typeText("1000")

        app.buttons["createMonthButton"].tap()

        // Home takes over, with the month's figures already derived.
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20),
                      "Home did not appear after creating the first month")
        assertLabel("homeSafeToSpend", contains: "1,400", in: app,
                    "Safe to Spend wrong for a brand new month")
        assertLabel("homeStartingMoney", contains: "2,400", in: app, "Starting money wrong")

        relaunch(app)
        assertLabel("homeSafeToSpend", contains: "1,400", in: app,
                    "The new month did not survive relaunch")
    }

    // MARK: - Home reactivity

    func testHomeFollowsTheLedger() {
        let app = launch(["-uiTestSeedMonth"])
        openTab("Home", in: app)

        assertLabel("homeSafeToSpend", contains: "1,400", in: app, "Wrong starting position")
        XCTAssertTrue(app.staticTexts["No Activity Yet"].exists,
                      "Empty activity state missing")

        // --- Spend 100 --------------------------------------------------------
        addExpenseFromHome("100", "Chipotle", in: app)
        openTab("Home", in: app)
        scrollToTop(app)
        assertLabel("homeSpent", contains: "100", in: app, "Spent did not react")
        assertLabel("homeSafeToSpend", contains: "1,300", in: app,
                    "Safe to Spend did not react to spending")

        // The expense shows in activity, reading as money going out.
        let activity = app.descendants(matching: .any)
            .matching(identifier: "activity-Chipotle").firstMatch
        scrollTo(activity, in: app, "The expense did not reach recent activity")
        XCTAssertTrue(activity.label.contains("-"),
                      "Expense should read as money out: \(activity.label)")

        // --- Add 50 -----------------------------------------------------------
        scrollTo(app.buttons["homeAddMoneyButton"], in: app, "Add Money not reachable")
        app.buttons["homeAddMoneyButton"].tap()
        let amount = app.textFields["moneyAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Add Money did not open")
        amount.tap(); amount.typeText("50")
        let source = app.textFields["moneySourceField"]
        source.tap(); source.typeText("Refund")
        app.buttons["saveMoneyButton"].tap()

        scrollToTop(app)
        assertLabel("homeMoneyAdded", contains: "50", in: app, "Money Added did not react")
        assertLabel("homeSafeToSpend", contains: "1,350", in: app,
                    "Safe to Spend did not react to money added")
    }

    // MARK: - Switching months

    func testSwitchingMonthsChangesEveryTab() {
        let app = launch(["-uiTestSeedMonth", "-uiTestSeedPreviousMonth", "-uiTestSeedExpense"])
        openTab("Home", in: app)

        // The current month: 2,400 starting, 1,000 protected, 14.72 spent.
        assertLabel("homeStartingMoney", contains: "2,400", in: app, "Wrong month selected")

        // --- Switch to the previous month (999 / 500) -------------------------
        app.buttons["monthSelectorButton"].firstMatch.tap()
        let options = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'monthOption-'")
        )
        XCTAssertTrue(options.element(boundBy: 0).waitForExistence(timeout: 10),
                      "The month list did not open")
        // Newest first, so index 1 is the previous month.
        options.element(boundBy: 1).tap()

        assertLabel("homeStartingMoney", contains: "999", in: app,
                    "Home did not follow the month change")
        assertLabel("homeSafeToSpend", contains: "499", in: app,
                    "Safe to Spend did not follow the month change")
        assertLabel("homeSpent", contains: "0", in: app,
                    "The previous month should have no spending")

        // Transactions and Plan must agree.
        openTab("Transactions", in: app)
        XCTAssertTrue(app.staticTexts["No Expenses Yet"].waitForExistence(timeout: 10),
                      "Transactions still showed the other month's expenses")

        openTab("Plan", in: app)
        assertLabel("summaryStartingMoney", contains: "999", in: app,
                    "Plan did not follow the month change")

        // --- Switch back ------------------------------------------------------
        app.buttons["monthSelectorButton"].firstMatch.tap()
        let backOptions = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'monthOption-'")
        )
        XCTAssertTrue(backOptions.element(boundBy: 0).waitForExistence(timeout: 10))
        backOptions.element(boundBy: 0).tap()

        assertLabel("summaryStartingMoney", contains: "2,400", in: app,
                    "Plan did not switch back")
        openTab("Transactions", in: app)
        XCTAssertTrue(app.buttons["expense-Chipotle"].waitForExistence(timeout: 10),
                      "The expense did not come back with its month")
    }

    // MARK: - Rollover

    func testStartNextMonthCarriesTheBalanceAndCopiesCategories() {
        let app = launch(["-uiTestSeedMonth"])

        // Spend 600 so there is something to carry: 2,400 - 600 = 1,800.
        addExpenseFromHome("600", "Various", in: app)

        openTab("Plan", in: app)
        scrollTo(app.buttons["startNextMonthButton"], in: app,
                 "Start Next Month not reachable")
        app.buttons["startNextMonthButton"].tap()

        let starting = app.textFields["startingMoneyField"]
        XCTAssertTrue(starting.waitForExistence(timeout: 10), "Rollover screen did not open")
        XCTAssertEqual(starting.value as? String, "1800",
                       "Starting money should default to what September had left")

        let protected = app.textFields["protectedMoneyField"]
        XCTAssertEqual(protected.value as? String, "1000",
                       "Protected money should carry over unchanged")

        app.buttons["createNextMonthButton"].tap()

        // The new month is selected, empty, and has the copied budget.
        openTab("Home", in: app)
        assertLabel("homeStartingMoney", contains: "1,800", in: app,
                    "The new month did not start with the carried balance")
        assertLabel("homeSpent", contains: "0", in: app,
                    "Expenses were carried into the new month")
        assertLabel("homeMoneyAdded", contains: "0", in: app,
                    "Money Added was carried into the new month")

        openTab("Plan", in: app)
        let copied = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Eating Out").firstMatch
        scrollTo(copied, in: app, "The category was not copied into the new month")
        XCTAssertTrue(copied.label.contains("200"), "Budget did not copy: \(copied.label)")

        relaunch(app)
        openTab("Home", in: app)
        assertLabel("homeStartingMoney", contains: "1,800", in: app,
                    "The rolled-over month did not survive relaunch")
    }

    // MARK: - Closing

    func testClosingAMonthMakesItReadOnlyAndSticks() {
        let app = launch(["-uiTestSeedMonth", "-uiTestSeedExpense", "-uiTestSeedMoneyAdded"])

        openTab("Plan", in: app)
        scrollTo(app.buttons["closeMonthButton"], in: app, "Close Month not reachable")
        app.buttons["closeMonthButton"].tap()

        let confirm = app.buttons["confirmCloseMonthButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                      "Closing did not ask for confirmation")
        confirm.tap()

        // Plan says so, and stops offering to change anything.
        XCTAssertTrue(app.staticTexts["Closed"].waitForExistence(timeout: 10)
                      || app.descendants(matching: .any)
                          .matching(identifier: "monthClosedLabel").firstMatch.exists,
                      "The month was not marked closed")
        XCTAssertFalse(app.buttons["addCategoryButton"].exists,
                       "A closed month still offered Add Category")
        XCTAssertFalse(app.buttons["editPlanMoneyButton"].exists,
                       "A closed month still offered to edit its money")
        XCTAssertFalse(app.buttons["addMoneyButton"].exists,
                       "A closed month still offered Add Money")

        // Home and Transactions must agree, not just Plan.
        openTab("Home", in: app)
        XCTAssertTrue(
            app.staticTexts["This month is closed and can no longer be edited."].exists,
            "Home did not show the month as closed"
        )
        XCTAssertFalse(app.buttons["homeAddExpenseButton"].exists,
                       "Home still offered Add Expense on a closed month")
        XCTAssertFalse(app.buttons["homeAddMoneyButton"].exists,
                       "Home still offered Add Money on a closed month")

        openTab("Transactions", in: app)
        XCTAssertFalse(app.buttons["addExpenseButton"].exists,
                       "Transactions still offered Add Expense on a closed month")

        // The history is still all there, and still editable-looking nowhere.
        let row = app.buttons["expense-Chipotle"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "Closing the month hid its expenses")
        row.tap()
        XCTAssertFalse(app.buttons["editExpenseButton"].exists,
                       "A closed month's expense could still be edited")
        XCTAssertFalse(app.buttons["deleteExpenseButton"].exists,
                       "A closed month's expense could still be deleted")

        relaunch(app)
        openTab("Plan", in: app)
        scrollUntilExists(app.descendants(matching: .any)
                            .matching(identifier: "monthClosedLabel").firstMatch,
                          in: app, "The month did not stay closed after relaunch")
        XCTAssertFalse(app.buttons["closeMonthButton"].exists,
                       "A closed month offered to close again")
    }
}
