import XCTest

/// Settings, export, and the restore flow, with real taps.
///
/// The native document picker cannot be driven reliably from XCTest, so the
/// restore tests stop where the picker takes over. Everything up to that point,
/// and everything after a file has been chosen, is covered by the unit suites
/// against real files -- the production import path is not weakened to make a
/// UI test easier.
final class SettingsFlowUITests: XCTestCase {

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

    private func openSettings(_ app: XCUIApplication) {
        openTab("Home", in: app)
        let button = app.buttons["settingsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The settings button was missing")
        button.tap()
        XCTAssertTrue(app.buttons["exportBackupButton"].waitForExistence(timeout: 10),
                      "Settings did not open")
    }

    private func dismissShareSheet(_ app: XCUIApplication) {
        if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
        } else {
            app.swipeDown()
        }
    }

    // MARK: - Settings

    func testSettingsOffersBackupAndNamesTheFormatVersion() {
        let app = launch()
        openSettings(app)

        XCTAssertTrue(app.buttons["exportBackupButton"].exists)
        XCTAssertTrue(app.buttons["restoreBackupButton"].exists)

        let version = app.descendants(matching: .any)
            .matching(identifier: "backupFormatVersion").firstMatch
        XCTAssertTrue(version.exists, "The backup format version was not shown")
        XCTAssertTrue(version.label.contains("1"),
                      "Expected format version 1 — got \"\(version.label)\"")
    }

    // MARK: - Export

    func testExportingABackupOpensTheShareSheet() {
        let app = launch(["-uiTestSeedExpense", "-uiTestSeedMoneyAdded"])
        openSettings(app)

        app.buttons["exportBackupButton"].tap()

        // The system share sheet, carrying a file named after the app.
        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        let namedFile = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'Finance-Notebook-Backup'"))
            .firstMatch
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 15)
                      || namedFile.waitForExistence(timeout: 5),
                      "The share sheet did not appear")

        dismissShareSheet(app)
        XCTAssertTrue(app.buttons["exportBackupButton"].waitForExistence(timeout: 10),
                      "Did not return to Settings after sharing")
    }

    /// Exporting must not disturb the notebook it copied.
    func testExportingLeavesTheNotebookAlone() {
        let app = launch(["-uiTestSeedExpense"])
        openSettings(app)
        app.buttons["exportBackupButton"].tap()

        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        _ = shareSheet.waitForExistence(timeout: 15)
        dismissShareSheet(app)

        app.buttons["Done"].firstMatch.tap()

        openTab("Transactions", in: app)
        XCTAssertTrue(app.buttons["expense-Chipotle"].waitForExistence(timeout: 10),
                      "The expense disappeared after an export")
    }

    // MARK: - Restore

    /// Restore opens the system file importer rather than asking anyone to
    /// paste JSON. Automation stops at the picker; what happens after a file is
    /// chosen is covered against real files in the unit suites.
    func testRestoreOpensTheSystemFileImporter() {
        let app = launch()
        openSettings(app)

        app.buttons["restoreBackupButton"].tap()

        // The picker is a separate process, so look for its chrome rather than
        // for anything the app owns.
        let picker = app.navigationBars.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 15),
                      "The file importer did not open")

        if app.buttons["Cancel"].firstMatch.exists {
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            app.swipeDown()
        }

        XCTAssertTrue(app.buttons["restoreBackupButton"].waitForExistence(timeout: 15),
                      "Cancelling the importer did not return to Settings")
    }

    /// Cancelling out of Settings must leave everything as it was.
    func testLeavingSettingsChangesNothing() {
        let app = launch(["-uiTestSeedExpense", "-uiTestSeedMoneyAdded"])

        openTab("Home", in: app)
        let before = app.descendants(matching: .any)
            .matching(identifier: "homeSafeToSpend").firstMatch.label

        openSettings(app)
        app.buttons["Done"].firstMatch.tap()

        openTab("Home", in: app)
        let after = app.descendants(matching: .any)
            .matching(identifier: "homeSafeToSpend").firstMatch.label
        XCTAssertEqual(before, after, "Visiting Settings changed the month")
    }
}
