import XCTest
@testable import FinanceNotebook

/// The shared wording. Worth testing because three screens now depend on these
/// producing the same sentence.
final class FinanceCopyTests: XCTestCase {

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    func testUnderBudgetReportsWhatIsLeft() {
        XCTAssertTrue(
            FinanceCopy.budgetStatus(spent: dec("150"), budget: dec("200"))
                .contains("50.00 remaining")
        )
    }

    func testExactlyOnBudgetIsNotOverBudget() {
        let status = FinanceCopy.budgetStatus(spent: dec("200"), budget: dec("200"))
        XCTAssertTrue(status.contains("remaining"), "Got \"\(status)\"")
        XCTAssertFalse(status.contains("over budget"))
    }

    /// "-$15.00 remaining" is not a sentence anyone says.
    func testOverBudgetReportsTheOverspendPositively() {
        let status = FinanceCopy.budgetStatus(spent: dec("215"), budget: dec("200"))
        XCTAssertTrue(status.contains("15.00 over budget"), "Got \"\(status)\"")
        XCTAssertFalse(status.contains("-"), "The overspend was rendered negative")
        XCTAssertFalse(status.contains("$-"), "Malformed negative currency")
    }

    func testAZeroBudgetWithNoSpendingSaysSo() {
        XCTAssertEqual(
            FinanceCopy.budgetStatus(spent: 0, budget: 0), "No budget set"
        )
    }

    func testAZeroBudgetWithSpendingIsEntirelyOver() {
        let status = FinanceCopy.budgetStatus(spent: dec("20"), budget: 0)
        XCTAssertTrue(status.contains("20.00 over budget"), "Got \"\(status)\"")
    }

    func testCategoryDeletionWarningSaysNothingIsLost() {
        let warning = FinanceCopy.categoryDeletionWarning(expenseCount: 3)
        XCTAssertTrue(warning.contains("3 expenses are"))
        XCTAssertTrue(warning.contains("NOT be deleted"))
        XCTAssertTrue(warning.contains("Uncategorized"))
        XCTAssertTrue(warning.contains("reassigned"),
                      "The warning does not say the situation is recoverable")
    }

    func testCategoryDeletionWarningReadsSinglyForOne() {
        let warning = FinanceCopy.categoryDeletionWarning(expenseCount: 1)
        XCTAssertTrue(warning.contains("1 expense is"))
        XCTAssertFalse(warning.contains("expenses are"))
    }

    func testAnEmptyCategoryWarningIsBrief() {
        XCTAssertEqual(
            FinanceCopy.categoryDeletionWarning(expenseCount: 0),
            "This category has no expenses."
        )
    }

    /// Reopening is not supported, so nothing should hint that it is.
    func testCloseMonthWarningNamesWhatSurvivesAndPromisesNoReopen() {
        XCTAssertTrue(FinanceCopy.closeMonthWarning.contains("Reviews and reports"))
        XCTAssertFalse(FinanceCopy.closeMonthWarning.lowercased().contains("reopen"))
        XCTAssertFalse(FinanceCopy.closeMonthWarning.lowercased().contains("undo"))
    }

    func testThereIsOneClosedMonthSentence() {
        XCTAssertEqual(FinanceCopy.closedMonthNotice,
                       "This month is closed and can no longer be edited.")
    }
}
