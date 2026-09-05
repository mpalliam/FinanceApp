import XCTest

/// Writing and re-reading reviews with real taps, and confirming they stay tied
/// to the month they were written about.
final class ReviewFlowUITests: XCTestCase {

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

    private func type(_ text: String, into identifier: String, in app: XCUIApplication) {
        let field = app.textFields[identifier]
        var attempts = 0
        while !field.exists && attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        field.tap()
        field.typeText(text)
    }

    /// Reads a field's value, scrolling to it first. Form rows render lazily,
    /// so a field below the fold is absent from the hierarchy entirely rather
    /// than merely off screen.
    private func value(of identifier: String, in app: XCUIApplication,
                       line: UInt = #line) -> String {
        let field = app.textFields[identifier]
        var attempts = 0
        while !field.exists && attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(field.exists, "\(identifier) never appeared", line: line)
        return field.value as? String ?? ""
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // MARK: - Weekly check-in

    func testWeeklyCheckInShowsTheMonthAndKeepsTheNote() {
        let app = launch(["-uiTestSeedExpense"])
        openTab("Review", in: app)

        XCTAssertTrue(app.staticTexts["No Reviews Yet"].waitForExistence(timeout: 10),
                      "The empty review state was missing")

        app.buttons["thisWeeksReviewLink"].tap()

        // The snapshot is derived, not stored: seeded month is 2,400 starting,
        // 1,000 protected, 14.72 spent.
        XCTAssertTrue(
            label("weeklySafeToSpend", in: app).contains("1,385.28"),
            "Safe to Spend wrong on the check-in — got \"\(label("weeklySafeToSpend", in: app))\""
        )
        XCTAssertTrue(label("weeklySpent", in: app).contains("14.72"),
                      "Spent wrong on the check-in")

        type("Cook at home at least four nights.", into: "weeklyReviewNoteField", in: app)
        app.buttons["saveWeeklyReviewButton"].tap()

        // Back on the list, the week now reads as written.
        XCTAssertTrue(app.buttons["thisWeeksReviewLink"].waitForExistence(timeout: 10),
                      "Did not return to the review list")
        XCTAssertEqual(app.buttons["thisWeeksReviewLink"].label, "View This Week's Review",
                       "The list did not register that the week was written")
        XCTAssertFalse(app.staticTexts["No Reviews Yet"].exists,
                       "The empty state persisted after writing a review")

        // Reopening shows what was written.
        app.buttons["thisWeeksReviewLink"].tap()
        let field = app.textFields["weeklyReviewNoteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Cook at home at least four nights.",
                       "The note did not come back")

        goBack(app)
        relaunch(app)
        openTab("Review", in: app)
        app.buttons["thisWeeksReviewLink"].tap()
        let afterRelaunch = app.textFields["weeklyReviewNoteField"]
        XCTAssertTrue(afterRelaunch.waitForExistence(timeout: 10))
        XCTAssertEqual(afterRelaunch.value as? String, "Cook at home at least four nights.",
                       "The note did not survive relaunch")
    }

    /// Opening a check-in and leaving without writing must not create a record.
    func testLeavingABlankCheckInCreatesNothing() {
        let app = launch()
        openTab("Review", in: app)

        app.buttons["thisWeeksReviewLink"].tap()
        XCTAssertTrue(app.textFields["weeklyReviewNoteField"].waitForExistence(timeout: 10))
        app.buttons["saveWeeklyReviewButton"].tap()

        XCTAssertTrue(app.staticTexts["No Reviews Yet"].waitForExistence(timeout: 10),
                      "An empty review record was created")
        XCTAssertEqual(app.buttons["thisWeeksReviewLink"].label, "Start This Week's Review")
    }

    // MARK: - Monthly reflection

    func testMonthlyReflectionSurvivesRelaunch() {
        let app = launch(["-uiTestSeedExpense", "-uiTestSeedMoneyAdded"])
        openTab("Review", in: app)

        app.buttons["monthlyReflectionLink"].tap()

        // Derived month summary: 2,400 + 100 - 14.72.
        let remaining = label("reflectionMoneyRemaining", in: app)
        XCTAssertTrue(remaining.contains("2,485.28"),
                      "Month summary wrong on the reflection — got \"\(remaining)\"")

        type("Yes, on eating out.", into: "spentMoreThanExpectedField", in: app)
        type("The second coffee.", into: "avoidablePurchaseField", in: app)
        type("The winter coat.", into: "worthwhilePurchaseField", in: app)
        type("Plan meals on Sunday.", into: "changeNextMonthField", in: app)

        app.buttons["saveMonthlyReflectionButton"].tap()

        XCTAssertTrue(app.buttons["monthlyReflectionLink"].waitForExistence(timeout: 10),
                      "Did not return to the review list")

        relaunch(app)
        openTab("Review", in: app)
        app.buttons["monthlyReflectionLink"].tap()

        XCTAssertEqual(value(of: "spentMoreThanExpectedField", in: app),
                       "Yes, on eating out.", "An answer did not survive relaunch")
        XCTAssertEqual(value(of: "avoidablePurchaseField", in: app),
                       "The second coffee.")
        XCTAssertEqual(value(of: "worthwhilePurchaseField", in: app),
                       "The winter coat.")
        XCTAssertEqual(value(of: "changeNextMonthField", in: app),
                       "Plan meals on Sunday.")
    }

    // MARK: - Scoping

    /// A review belongs to the month it was written about, and must not follow
    /// the user into another one.
    func testReviewsStayWithTheirOwnMonth() {
        let app = launch(["-uiTestSeedPreviousMonth"])
        openTab("Review", in: app)

        // Write this month's reflection.
        app.buttons["monthlyReflectionLink"].tap()
        type("This month's words.", into: "spentMoreThanExpectedField", in: app)
        app.buttons["saveMonthlyReflectionButton"].tap()
        XCTAssertTrue(app.buttons["monthlyReflectionLink"].waitForExistence(timeout: 10))

        // Switch to the previous month: the reflection must not come along.
        app.buttons["monthSelectorButton"].firstMatch.tap()
        let options = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'monthOption-'")
        )
        XCTAssertTrue(options.element(boundBy: 0).waitForExistence(timeout: 10))
        options.element(boundBy: 1).tap()

        XCTAssertTrue(app.staticTexts["No Reviews Yet"].waitForExistence(timeout: 10),
                      "The previous month showed another month's review")

        app.buttons["monthlyReflectionLink"].tap()
        let field = app.textFields["spentMoreThanExpectedField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let existing = field.value as? String ?? ""
        XCTAssertTrue(existing.isEmpty || existing == "Optional",
                      "The previous month was pre-filled with another month's answer")

        type("The earlier month's words.", into: "spentMoreThanExpectedField", in: app)
        app.buttons["saveMonthlyReflectionButton"].tap()
        XCTAssertTrue(app.buttons["monthlyReflectionLink"].waitForExistence(timeout: 10))

        // Switch back: this month's own words return, unchanged.
        app.buttons["monthSelectorButton"].firstMatch.tap()
        let backOptions = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'monthOption-'")
        )
        XCTAssertTrue(backOptions.element(boundBy: 0).waitForExistence(timeout: 10))
        backOptions.element(boundBy: 0).tap()

        app.buttons["monthlyReflectionLink"].tap()
        let returned = app.textFields["spentMoreThanExpectedField"]
        XCTAssertTrue(returned.waitForExistence(timeout: 10))
        XCTAssertEqual(returned.value as? String, "This month's words.",
                       "The month's own reflection did not come back")
    }

    // MARK: - Closed months

    /// Closing settles the money, not the reflection.
    func testAClosedMonthStillAcceptsReviews() {
        let app = launch(["-uiTestSeedExpense"])

        // Close the month through the production UI.
        openTab("Plan", in: app)
        let closeButton = app.buttons["closeMonthButton"]
        var attempts = 0
        while !closeButton.isHittable && attempts < 12 { app.swipeUp(); attempts += 1 }
        XCTAssertTrue(closeButton.isHittable, "Close Month not reachable")
        closeButton.tap()
        app.buttons["confirmCloseMonthButton"].firstMatch.tap()

        // Money is frozen.
        openTab("Home", in: app)
        XCTAssertFalse(app.buttons["homeAddExpenseButton"].exists,
                       "A closed month still offered Add Expense")

        // Reflection is not.
        openTab("Review", in: app)
        app.buttons["monthlyReflectionLink"].tap()
        type("Closed, but still worth thinking about.",
             into: "spentMoreThanExpectedField", in: app)
        app.buttons["saveMonthlyReflectionButton"].tap()

        XCTAssertTrue(app.buttons["monthlyReflectionLink"].waitForExistence(timeout: 10),
                      "Saving a reflection on a closed month failed")

        app.buttons["monthlyReflectionLink"].tap()
        XCTAssertEqual(app.textFields["spentMoreThanExpectedField"].value as? String,
                       "Closed, but still worth thinking about.",
                       "The reflection on a closed month was not saved")
    }
}
