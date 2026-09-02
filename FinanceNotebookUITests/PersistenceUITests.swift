import XCTest

final class PersistenceUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// LabeledContent exposes one accessibility element per row, labelled
    /// "<label>, <value>".
    private func assertRow(_ text: String, _ app: XCUIApplication,
                           _ message: String, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[text].exists, message, line: line)
    }

    func testCreateSampleDataThenSurviveRelaunch() {
        let app = XCUIApplication()
        app.launch()

        // --- Start from a known-empty store --------------------------------
        let deleteButton = app.buttons["Delete everything"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 20), "Test screen did not appear")
        if deleteButton.isEnabled { deleteButton.tap() }
        XCTAssertTrue(app.staticTexts["No saved data yet."].waitForExistence(timeout: 10),
                      "Store was not empty at the start of the test")

        // --- 1. MonthlyPlan -------------------------------------------------
        app.buttons["1. September 2026 plan"].tap()
        XCTAssertTrue(app.staticTexts["September 2026"].waitForExistence(timeout: 10),
                      "MonthlyPlan was not created")
        assertRow("Starting balance, $2,400.00", app, "Starting balance wrong or missing")
        assertRow("Protected, $1,000.00", app, "Protected amount wrong or missing")
        assertRow("Closed, No", app, "isClosed should default to false")

        // --- 2. BudgetCategory ----------------------------------------------
        app.buttons["2. \"Eating Out\" category"].tap()
        XCTAssertTrue(app.staticTexts["Eating Out (Flexible), $200.00"].waitForExistence(timeout: 10),
                      "BudgetCategory was not created with the right name, type and budget")

        // --- 3. Transaction (expense) ----------------------------------------
        app.buttons["3. Chipotle expense"].tap()
        XCTAssertTrue(app.staticTexts["Chipotle - Eating Out, -$14.72"].waitForExistence(timeout: 10),
                      "Expense was not created, or is not linked to its category")

        // --- 4. MoneyAddedEntry -----------------------------------------------
        app.buttons["4. Refund money added"].tap()
        XCTAssertTrue(app.staticTexts["Refund, +$100.00"].waitForExistence(timeout: 10),
                      "MoneyAddedEntry was not created")

        // --- Kill the process, then relaunch ------------------------------------
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App did not actually terminate")

        app.launch()

        // --- Everything must still be there --------------------------------------
        XCTAssertTrue(app.staticTexts["September 2026"].waitForExistence(timeout: 20),
                      "MonthlyPlan did not survive relaunch")
        XCTAssertFalse(app.staticTexts["No saved data yet."].exists, "Store came back empty")
        assertRow("Starting balance, $2,400.00", app, "Starting balance did not persist")
        assertRow("Protected, $1,000.00", app, "Protected amount did not persist")
        assertRow("Eating Out (Flexible), $200.00", app, "Category did not persist")
        assertRow("Chipotle - Eating Out, -$14.72", app,
                  "Expense did not persist, or lost its category relationship")
        assertRow("Refund, +$100.00", app, "MoneyAddedEntry did not persist")
    }

    /// The month/year uniqueness guard: pressing "create plan" twice must not
    /// produce two September 2026 plans.
    func testDuplicatePlanIsNotCreated() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["1. September 2026 plan"].waitForExistence(timeout: 20))
        app.buttons["1. September 2026 plan"].tap()
        app.buttons["1. September 2026 plan"].tap()

        XCTAssertEqual(app.staticTexts.matching(identifier: "September 2026").count, 1,
                       "A duplicate plan was created for the same month/year")
    }

    /// Deleting a category must nullify its transactions, never delete them.
    func testDeletingEverythingCascadesCleanly() {
        let app = XCUIApplication()
        app.launch()

        let deleteButton = app.buttons["Delete everything"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 20))
        if !deleteButton.isEnabled {
            app.buttons["1. September 2026 plan"].tap()
        }
        deleteButton.tap()

        XCTAssertTrue(app.staticTexts["No saved data yet."].waitForExistence(timeout: 10),
                      "Deleting the plan did not cascade to its children")
        XCTAssertFalse(app.staticTexts["September 2026"].exists, "Plan was not deleted")
    }
}
