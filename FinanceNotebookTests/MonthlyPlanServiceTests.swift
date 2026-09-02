import XCTest
import SwiftData
@testable import FinanceNotebook

final class MonthlyPlanServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: MonthlyPlan.self, BudgetCategory.self, Expense.self, MoneyAddedEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func planCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MonthlyPlan>())
    }

    // MARK: - Creation

    func testCreatesPlanWithGivenValues() throws {
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: 2400, protectedAmount: 1000,
            context: context
        )

        XCTAssertEqual(plan.month, 9)
        XCTAssertEqual(plan.year, 2026)
        XCTAssertEqual(plan.startingBalance, 2400)
        XCTAssertEqual(plan.protectedAmount, 1000)
        XCTAssertFalse(plan.isClosed)
        XCTAssertEqual(try planCount(), 1)
    }

    // MARK: - Uniqueness

    func testRejectsDuplicatePlanForSameMonthAndYear() throws {
        try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )

        XCTAssertThrowsError(
            try MonthlyPlanService.createPlan(
                month: 9, year: 2026, startingBalance: 999, protectedAmount: 0, context: context
            )
        ) { error in
            XCTAssertEqual(error as? MonthlyPlanError, .planAlreadyExists(month: 9, year: 2026))
        }

        XCTAssertEqual(try planCount(), 1, "The rejected plan must not have been inserted")
    }

    func testSameMonthInADifferentYearIsAllowed() throws {
        try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )
        try MonthlyPlanService.createPlan(
            month: 9, year: 2027, startingBalance: 100, protectedAmount: 0, context: context
        )

        XCTAssertEqual(try planCount(), 2)
    }

    // MARK: - Validation

    func testRejectsInvalidMonths() throws {
        for month in [0, 13, -1, 99] {
            XCTAssertThrowsError(
                try MonthlyPlanService.createPlan(
                    month: month, year: 2026,
                    startingBalance: 100, protectedAmount: 0, context: context
                ),
                "month \(month) should have been rejected"
            ) { error in
                XCTAssertEqual(error as? MonthlyPlanError, .invalidMonth(month))
            }
        }
        XCTAssertEqual(try planCount(), 0)
    }

    func testAcceptsEveryValidMonth() throws {
        for month in 1...12 {
            try MonthlyPlanService.createPlan(
                month: month, year: 2026,
                startingBalance: 100, protectedAmount: 0, context: context
            )
        }
        XCTAssertEqual(try planCount(), 12)
    }

    func testRejectsNegativeStartingBalance() throws {
        XCTAssertThrowsError(
            try MonthlyPlanService.createPlan(
                month: 9, year: 2026,
                startingBalance: -1, protectedAmount: 0, context: context
            )
        ) { error in
            XCTAssertEqual(error as? MonthlyPlanError, .negativeStartingBalance)
        }
        XCTAssertEqual(try planCount(), 0)
    }

    func testRejectsNegativeProtectedAmount() throws {
        XCTAssertThrowsError(
            try MonthlyPlanService.createPlan(
                month: 9, year: 2026,
                startingBalance: 100, protectedAmount: -0.01, context: context
            )
        ) { error in
            XCTAssertEqual(error as? MonthlyPlanError, .negativeProtectedAmount)
        }
        XCTAssertEqual(try planCount(), 0)
    }

    func testZeroAmountsAreAllowed() throws {
        try MonthlyPlanService.createPlan(
            month: 1, year: 2026, startingBalance: 0, protectedAmount: 0, context: context
        )
        XCTAssertEqual(try planCount(), 1)
    }

    /// Money added later in the month can make this legitimate, so it is
    /// deliberately not an error.
    func testProtectedAmountMayExceedStartingBalance() throws {
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: 100, protectedAmount: 500, context: context
        )
        XCTAssertEqual(plan.protectedAmount, 500)
        XCTAssertEqual(try planCount(), 1)
    }
}
