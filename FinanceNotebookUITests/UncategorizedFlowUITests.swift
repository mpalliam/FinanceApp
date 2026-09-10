import XCTest

/// Cleaning up uncategorized spending with real taps.
final class UncategorizedFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

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

    /// List rows render lazily, so anything below the fold is absent until
    /// scrolled to.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication,
                          _ message: String, line: UInt = #line) {
        var attempts = 0
        while !element.exists && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists, message, line: line)
    }

    private func openUncategorized(_ app: XCUIApplication) {
        openTab("Plan", in: app)
        let link = app.buttons["uncategorizedLink"]
        scrollTo(link, in: app, "The uncategorized link was missing from Plan")
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(identifier: "uncategorizedView").firstMatch
                        .waitForExistence(timeout: 15),
                      "The uncategorized screen did not open")
    }

    /// The chooser is a sheet, so its rows carry proper identifiers.
    private func chooseCategory(_ name: String, in app: XCUIApplication,
                                line: UInt = #line) {
        let button = app.buttons["assignTo-\(name)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15),
                      "The category chooser did not offer \(name)", line: line)
        button.tap()
    }

    private func label(_ identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        guard element.waitForExistence(timeout: 10) else { return "" }
        return element.label
    }

    // MARK: - Bulk cleanup

    func testBulkAssigningUncategorizedExpenses() {
        let app = launch(["-uiTestSeedUncategorized"])
        openUncategorized(app)

        // Seeded: 9.88 + 21.50 + 4.25 = 35.63 with no budget.
        XCTAssertTrue(label("uncategorizedCount", in: app).contains("3"),
                      "Expected three uncategorized expenses")
        XCTAssertTrue(label("uncategorizedTotal", in: app).contains("35.63"),
                      "Uncategorized total wrong")

        // Pick two of the three.
        app.buttons["uncategorized-Taco Bell"].firstMatch.tap()
        app.buttons["uncategorized-Uber"].firstMatch.tap()

        let assign = app.buttons["assignCategoryButton"]
        XCTAssertTrue(assign.waitForExistence(timeout: 10))
        XCTAssertTrue(assign.label.contains("2"),
                      "The button did not report the selection — got \"\(assign.label)\"")
        assign.tap()

        chooseCategory("Eating Out", in: app)

        // The two chosen are gone; the third is not.
        XCTAssertTrue(label("uncategorizedCount", in: app).contains("1"),
                      "The assigned expenses did not leave the list")
        XCTAssertTrue(label("uncategorizedTotal", in: app).contains("4.25"),
                      "Only the unselected expense should remain")
        XCTAssertFalse(app.buttons["uncategorized-Taco Bell"].firstMatch.exists)
        XCTAssertTrue(app.buttons["uncategorized-Newsstand"].firstMatch.exists,
                      "An unselected expense was reassigned")

        // The month spent the same money either way; it is just filed now.
        app.buttons["doneUncategorizedButton"].tap()
        let category = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Eating Out").firstMatch
        scrollTo(category, in: app, "The category row was missing")
        XCTAssertTrue(category.label.contains("31.38"),
                      "The category did not receive the spending — got \"\(category.label)\"")

        openTab("Home", in: app)
        XCTAssertTrue(label("homeSpent", in: app).contains("35.63"),
                      "Reassigning changed what the month spent")
    }

    func testAssigningEverythingClearsTheSection() {
        let app = launch(["-uiTestSeedUncategorized"])
        openUncategorized(app)

        app.buttons["toggleSelectAllButton"].tap()
        app.buttons["assignCategoryButton"].tap()
        chooseCategory("Eating Out", in: app)

        XCTAssertTrue(app.staticTexts["All Caught Up"].waitForExistence(timeout: 10),
                      "The empty state did not appear after tidying everything")

        // And Plan stops mentioning it at all.
        app.buttons["doneUncategorizedButton"].tap()
        XCTAssertFalse(app.buttons["uncategorizedLink"].exists,
                       "Plan still offered cleanup with nothing left to clean")
    }

    /// A month with nothing to tidy should not be nagged about it.
    func testACleanMonthHasNoUncategorizedSection() {
        let app = launch(["-uiTestSeedExpense"])
        openTab("Plan", in: app)

        // Scroll the whole screen; the link must not be anywhere on it.
        for _ in 0..<10 { app.swipeUp() }
        XCTAssertFalse(app.buttons["uncategorizedLink"].exists,
                       "A tidy month was offered cleanup it does not need")
    }

    // MARK: - Closed months

    /// A closed month can be read but not tidied.
    func testAClosedMonthCanBeViewedButNotTidied() {
        let app = launch(["-uiTestSeedUncategorized"])

        openTab("Plan", in: app)
        let close = app.buttons["closeMonthButton"]
        scrollTo(close, in: app, "Close Month was not reachable")
        close.tap()
        app.buttons["confirmCloseMonthButton"].firstMatch.tap()

        openUncategorized(app)

        // Still readable.
        XCTAssertTrue(label("uncategorizedCount", in: app).contains("3"),
                      "A closed month hid its uncategorized spending")
        XCTAssertTrue(app.staticTexts[
            "This month is closed and can no longer be edited."
        ].exists, "The closed month was not explained")

        // But not tidyable.
        XCTAssertFalse(app.buttons["assignCategoryButton"].exists,
                       "A closed month still offered to reassign")
        XCTAssertFalse(app.buttons["toggleSelectAllButton"].exists,
                       "A closed month still offered selection")
    }

    // MARK: - Category deletion feeds cleanup

    func testDeletingACategoryExplainsAndFeedsTheCleanupScreen() {
        let app = launch(["-uiTestSeedExpense"])
        openTab("Plan", in: app)

        let row = app.descendants(matching: .any)
            .matching(identifier: "categoryRow-Eating Out").firstMatch
        scrollTo(row, in: app, "The category row was missing")
        row.swipeLeft()
        app.buttons["swipeDeleteCategoryButton"].firstMatch.tap()

        XCTAssertTrue(app.buttons["confirmDeleteCategoryButton"].firstMatch
                        .waitForExistence(timeout: 10),
                      "Deleting a category did not ask first")
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'reassigned'")
            ).firstMatch.exists,
            "The warning did not say the expenses could be reassigned later"
        )

        app.buttons["confirmDeleteCategoryButton"].firstMatch.tap()

        // The spending survived and is now reachable for cleanup.
        let link = app.buttons["uncategorizedLink"]
        scrollTo(link, in: app, "The deleted category's spending was not offered for cleanup")
        link.tap()
        XCTAssertTrue(app.buttons["uncategorized-Chipotle"].firstMatch
                        .waitForExistence(timeout: 10),
                      "The expense did not survive its category being deleted")
    }
}
