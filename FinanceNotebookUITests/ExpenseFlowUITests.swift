import XCTest

/// The real user journey, driven by taps: add an expense, edit it, delete it,
/// and confirm each result survives killing and relaunching the app.
final class ExpenseFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launches with a known store. Seeding happens through launch arguments so
    /// the production UI never carries test-only buttons.
    private func launch(seedExpense: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeedMonth"]
        if seedExpense {
            app.launchArguments.append("-uiTestSeedExpense")
        }
        app.launch()
        openTransactions(app)
        return app
    }

    /// Home is the first tab now, so the expense list has to be selected.
    private func openTransactions(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Transactions"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Transactions tab never appeared")
        tab.tap()
    }

    /// Relaunches with no arguments, so nothing is reset or seeded and only what
    /// was persisted can appear.
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
        openTransactions(app)
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "A form field never appeared")
        field.tap()
        field.typeText(text)
    }

    private func chipotleRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["expense-Chipotle"]
    }

    // MARK: - Add

    func testAddExpenseThenSurviveRelaunch() {
        let app = launch()

        XCTAssertTrue(app.buttons["addExpenseButton"].waitForExistence(timeout: 20),
                      "Expense list never appeared")
        app.buttons["addExpenseButton"].tap()

        type("14.72", into: app.textFields["amountField"])
        type("Chipotle", into: app.textFields["merchantField"])

        app.buttons["saveExpenseButton"].tap()

        let row = chipotleRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "Chipotle did not appear in the expense list after saving")
        XCTAssertTrue(row.label.contains("14.72"),
                      "Row did not show the amount: \(row.label)")
        XCTAssertTrue(row.label.contains("Eating Out"),
                      "Row did not show the category: \(row.label)")

        relaunch(app)

        let afterRelaunch = chipotleRow(app)
        XCTAssertTrue(afterRelaunch.waitForExistence(timeout: 20),
                      "Chipotle did not survive relaunch")
        XCTAssertTrue(afterRelaunch.label.contains("14.72"),
                      "Amount did not survive relaunch: \(afterRelaunch.label)")
    }

    func testEmptyStateIsShownBeforeAnyExpenseExists() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["No Expenses Yet"].waitForExistence(timeout: 20),
                      "Empty state was not shown for a month with no expenses")
    }

    // MARK: - Edit

    func testEditExpenseAmountThenSurviveRelaunch() {
        let app = launch(seedExpense: true)

        let row = chipotleRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Seeded expense never appeared")
        XCTAssertTrue(row.label.contains("14.72"))
        row.tap()

        XCTAssertTrue(app.buttons["editExpenseButton"].waitForExistence(timeout: 10),
                      "Expense detail did not open")
        app.buttons["editExpenseButton"].tap()

        let amountField = app.textFields["amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 10), "Edit form did not open")
        amountField.tap()
        if let existing = amountField.value as? String, !existing.isEmpty {
            amountField.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            )
        }
        amountField.typeText("18.25")

        app.buttons["saveExpenseButton"].tap()

        // Back on the detail screen, then back to the list.
        XCTAssertTrue(app.buttons["editExpenseButton"].waitForExistence(timeout: 10),
                      "Did not return to the expense detail after saving")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let updated = chipotleRow(app)
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
        XCTAssertTrue(updated.label.contains("18.25"),
                      "Edited amount did not appear in the list: \(updated.label)")

        relaunch(app)

        let afterRelaunch = chipotleRow(app)
        XCTAssertTrue(afterRelaunch.waitForExistence(timeout: 20),
                      "Edited expense did not survive relaunch")
        XCTAssertTrue(afterRelaunch.label.contains("18.25"),
                      "Edited amount did not persist: \(afterRelaunch.label)")
        XCTAssertFalse(afterRelaunch.label.contains("14.72"),
                       "The original amount came back after relaunch")
    }

    // MARK: - Delete

    func testDeleteExpenseThenStayDeletedAfterRelaunch() {
        let app = launch(seedExpense: true)

        let row = chipotleRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Seeded expense never appeared")
        row.tap()

        XCTAssertTrue(app.buttons["deleteExpenseButton"].waitForExistence(timeout: 10),
                      "Expense detail did not open")
        app.buttons["deleteExpenseButton"].tap()

        // Deleting money records must always ask first.
        let confirm = app.buttons["confirmDeleteButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                      "Delete did not ask for confirmation")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["No Expenses Yet"].waitForExistence(timeout: 10),
                      "List did not update after deleting the only expense")
        XCTAssertFalse(chipotleRow(app).exists, "Deleted expense is still listed")

        relaunch(app)

        XCTAssertTrue(app.staticTexts["No Expenses Yet"].waitForExistence(timeout: 20),
                      "Deleted expense came back after relaunch")
        XCTAssertFalse(chipotleRow(app).exists, "Deleted expense came back after relaunch")
    }

    /// A swipe must not destroy a financial record on its own.
    func testSwipeToDeleteAsksForConfirmationFirst() {
        let app = launch(seedExpense: true)

        let row = chipotleRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.swipeLeft()

        app.buttons["swipeDeleteExpenseButton"].firstMatch.tap()

        XCTAssertTrue(app.buttons["confirmDeleteFromListButton"].firstMatch
                        .waitForExistence(timeout: 10),
                      "Swipe-to-delete removed the expense without confirmation")

        // The dialog is presented as a popover here, where the cancel button is
        // not drawn: dismissing means tapping outside it.
        let cancel = app.buttons["cancelDeleteFromListButton"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }
        XCTAssertTrue(chipotleRow(app).waitForExistence(timeout: 10),
                      "Cancelling the confirmation still deleted the expense")
    }
}
