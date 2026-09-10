import XCTest

/// Proves the money on screen is derived from the expense records, by changing
/// the records through the UI and watching the totals follow.
final class PlanFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(seedExpense: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeedMonth"]
        if seedExpense {
            app.launchArguments.append("-uiTestSeedExpense")
        }
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

    private func openPlan(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Plan tab never appeared")
        tab.tap()
    }

    private func openExpenses(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Transactions"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Transactions tab never appeared")
        tab.tap()
    }

    /// Reads a summary row by identifier without assuming its element type.
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

    /// Waits for an element to go away, rather than asserting the instant after
    /// a tap and racing the UI update.
    private func waitForDisappearance(
        _ element: XCUIElement, _ message: String, line: UInt = #line
    ) {
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: element
        )
        let result = XCTWaiter.wait(for: [gone], timeout: 10)
        XCTAssertEqual(result, .completed, message, line: line)
    }

    private func addExpense(_ amount: String, merchant: String, in app: XCUIApplication) {
        openExpenses(app)
        app.buttons["addExpenseButton"].tap()

        let amountField = app.textFields["amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 10))
        amountField.tap()
        amountField.typeText(amount)

        let merchantField = app.textFields["merchantField"]
        merchantField.tap()
        merchantField.typeText(merchant)

        app.buttons["saveExpenseButton"].tap()
        XCTAssertTrue(app.buttons["expense-\(merchant)"].waitForExistence(timeout: 10),
                      "Expense was not created")
    }

    // MARK: - Reactivity

    /// Add, edit and delete an expense; Safe to Spend must follow every time.
    func testSafeToSpendFollowsExpenseChanges() {
        let app = launch()

        // Seeded month: starting 2,400, protected 1,000, nothing spent.
        openPlan(app)
        assertSummary("summarySafeToSpend", contains: "1,400", in: app,
                      "Safe to Spend wrong before any spending")
        assertSummary("summaryTotalMoney", contains: "2,400", in: app, "Total Money wrong")
        assertSummary("summarySpent", contains: "0", in: app, "Spent should start at zero")

        // --- Add $100 -----------------------------------------------------
        addExpense("100", merchant: "Chipotle", in: app)
        openPlan(app)
        assertSummary("summarySpent", contains: "100", in: app,
                      "Spent did not include the new expense")
        assertSummary("summaryMoneyRemaining", contains: "2,300", in: app,
                      "Money Remaining did not react")
        assertSummary("summarySafeToSpend", contains: "1,300", in: app,
                      "Safe to Spend did not react to adding an expense")

        // --- Edit to $150 -------------------------------------------------
        openExpenses(app)
        app.buttons["expense-Chipotle"].tap()
        app.buttons["editExpenseButton"].tap()

        let amountField = app.textFields["amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 10))
        amountField.tap()
        if let existing = amountField.value as? String, !existing.isEmpty {
            amountField.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            )
        }
        amountField.typeText("150")
        app.buttons["saveExpenseButton"].tap()
        XCTAssertTrue(app.buttons["editExpenseButton"].waitForExistence(timeout: 10))

        openPlan(app)
        assertSummary("summarySafeToSpend", contains: "1,250", in: app,
                      "Safe to Spend did not react to editing an expense")

        // --- Delete -------------------------------------------------------
        openExpenses(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["expense-Chipotle"].tap()
        app.buttons["deleteExpenseButton"].tap()
        app.buttons["confirmDeleteButton"].firstMatch.tap()

        openPlan(app)
        assertSummary("summarySafeToSpend", contains: "1,400", in: app,
                      "Safe to Spend did not return to its original value after deletion")
        assertSummary("summarySpent", contains: "0", in: app,
                      "Spent did not return to zero after deletion")
    }

    /// Safe to Spend must be allowed to read negative.
    func testSafeToSpendGoesNegativeAndIsReadable() {
        let app = launch()

        openPlan(app)
        app.buttons["editPlanMoneyButton"].tap()

        let starting = app.textFields["startingMoneyField"]
        XCTAssertTrue(starting.waitForExistence(timeout: 10))
        starting.tap()
        if let existing = starting.value as? String, !existing.isEmpty {
            starting.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            )
        }
        starting.typeText("900")
        app.buttons["savePlanMoneyButton"].tap()

        let label = summaryLabel("summarySafeToSpend", in: app)
        XCTAssertTrue(label.contains("100"), "Expected -$100 Safe to Spend, got \"\(label)\"")
        XCTAssertTrue(label.contains("-"), "Negative Safe to Spend lost its sign: \"\(label)\"")
        XCTAssertFalse(label.contains("$-"), "Malformed negative currency: \"\(label)\"")
    }

    // MARK: - Editing the month's money, and persistence

    func testEditingStartingAndProtectedMoneyPersists() {
        let app = launch()

        openPlan(app)
        app.buttons["editPlanMoneyButton"].tap()

        let starting = app.textFields["startingMoneyField"]
        XCTAssertTrue(starting.waitForExistence(timeout: 10))
        starting.tap()
        if let existing = starting.value as? String, !existing.isEmpty {
            starting.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            )
        }
        starting.typeText("2500")
        app.buttons["savePlanMoneyButton"].tap()

        assertSummary("summaryStartingMoney", contains: "2,500", in: app,
                      "Starting money did not update")
        assertSummary("summarySafeToSpend", contains: "1,500", in: app,
                      "Safe to Spend did not follow the new starting money")

        relaunch(app)
        openPlan(app)
        assertSummary("summaryStartingMoney", contains: "2,500", in: app,
                      "Starting money did not survive relaunch")
    }

    // MARK: - Category management

    func testAddEditCategoryAndPersistAcrossRelaunch() {
        let app = launch()
        openPlan(app)

        // --- Add ------------------------------------------------------------
        app.buttons["addCategoryButton"].tap()

        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Add Category did not open")
        nameField.tap()
        nameField.typeText("Groceries")

        let budgetField = app.textFields["categoryBudgetField"]
        budgetField.tap()
        budgetField.typeText("200")

        app.buttons["saveCategoryButton"].tap()

        let row = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Groceries").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New category did not appear")
        XCTAssertTrue(row.label.contains("200"), "Budget missing from row: \(row.label)")

        // --- Edit the budget to 250 ------------------------------------------
        row.tap()
        let editBudget = app.textFields["categoryBudgetField"]
        XCTAssertTrue(editBudget.waitForExistence(timeout: 10), "Edit Category did not open")
        editBudget.tap()
        if let existing = editBudget.value as? String, !existing.isEmpty {
            editBudget.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            )
        }
        editBudget.typeText("250")
        app.buttons["saveCategoryButton"].tap()

        let updated = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Groceries").firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
        XCTAssertTrue(updated.label.contains("250"),
                      "Edited budget did not appear: \(updated.label)")

        // --- Survives relaunch ------------------------------------------------
        relaunch(app)
        openPlan(app)
        let afterRelaunch = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Groceries").firstMatch
        XCTAssertTrue(afterRelaunch.waitForExistence(timeout: 20),
                      "Category did not survive relaunch")
        XCTAssertTrue(afterRelaunch.label.contains("250"),
                      "Edited budget did not persist: \(afterRelaunch.label)")
    }

    /// Deleting a category with expenses must say plainly that the expenses live.
    func testDeletingACategoryWithExpensesWarnsAndKeepsTheSpending() {
        let app = launch(seedExpense: true)
        openPlan(app)

        // The seeded $14.72 Chipotle expense is in Eating Out.
        assertSummary("summarySpent", contains: "14.72", in: app, "Seeded expense missing")

        let row = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Eating Out").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded category missing")
        row.swipeLeft()
        app.buttons["swipeDeleteCategoryButton"].firstMatch.tap()

        XCTAssertTrue(app.buttons["confirmDeleteCategoryButton"].firstMatch
                        .waitForExistence(timeout: 10),
                      "Deleting a category did not ask for confirmation")

        let warned = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'will NOT be deleted'")
        ).firstMatch
        XCTAssertTrue(warned.exists,
                      "The confirmation did not say the expenses would be kept")

        app.buttons["confirmDeleteCategoryButton"].firstMatch.tap()

        // The category is gone, but its money is not.
        waitForDisappearance(
            app.descendants(matching: .any)
                .matching(identifier: "categoryRow-Eating Out").firstMatch,
            "The category was not deleted"
        )
        assertSummary("summarySpent", contains: "14.72", in: app,
                      "Deleting a category erased its spending from the month")
        // Plan's uncategorized row is now a way into the cleanup screen rather
        // than a read-only total.
        let uncategorized = app.buttons["uncategorizedLink"]
        var attempts = 0
        while !uncategorized.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(uncategorized.exists,
                      "The orphaned expense is not offered for cleanup")
        XCTAssertTrue(uncategorized.label.contains("14.72"),
                      "Uncategorized spending wrong — got \"\(uncategorized.label)\"")

        // And the expense itself is still listed, just without a category.
        openExpenses(app)
        let expenseRow = app.buttons["expense-Chipotle"]
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 10),
                      "The expense was deleted along with its category")
        XCTAssertTrue(expenseRow.label.contains("Uncategorized"),
                      "Expense should now read Uncategorized: \(expenseRow.label)")
    }
}
