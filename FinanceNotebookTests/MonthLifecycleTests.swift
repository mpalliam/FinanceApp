import XCTest
import SwiftData
@testable import FinanceNotebook

/// Creating months, working out which month comes next, and rolling one into
/// the next.
final class MonthLifecycleTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @discardableResult
    private func makeSeptember(
        starting: String = "2400", protected: String = "1000"
    ) throws -> MonthlyPlan {
        try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec(starting), protectedAmount: dec(protected),
            context: context
        )
    }

    // MARK: - Creation

    func testCreatesAMonth() throws {
        let plan = try makeSeptember()
        XCTAssertEqual(plan.monthKey, "2026-09")
        XCTAssertEqual(plan.startingBalance, dec("2400"))
        XCTAssertEqual(plan.protectedAmount, dec("1000"))
        XCTAssertFalse(plan.isClosed)
        XCTAssertTrue(plan.categories.isEmpty, "A new month may start with no categories")
    }

    func testRejectsADuplicateMonth() throws {
        try makeSeptember()
        XCTAssertThrowsError(try makeSeptember(starting: "50")) {
            XCTAssertEqual($0 as? MonthlyPlanError, .planAlreadyExists(month: 9, year: 2026))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1)
    }

    func testCreatesAnArbitraryMonth() throws {
        let plan = try MonthlyPlanService.createPlan(
            month: 1, year: 2027, startingBalance: dec("100"), protectedAmount: .zero,
            context: context
        )
        XCTAssertEqual(plan.monthKey, "2027-01")
    }

    func testExistingValidationStillApplies() throws {
        XCTAssertThrowsError(
            try MonthlyPlanService.createPlan(
                month: 13, year: 2026, startingBalance: dec("1"), protectedAmount: .zero,
                context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError, .invalidMonth(13)) }

        XCTAssertThrowsError(
            try MonthlyPlanService.createPlan(
                month: 9, year: 2026, startingBalance: dec("-1"), protectedAmount: .zero,
                context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError, .negativeStartingBalance) }
    }

    // MARK: - Next month

    func testNextMonthWithinTheSameYear() throws {
        let plan = try makeSeptember()
        let next = MonthlyPlanService.nextMonth(after: plan)
        XCTAssertEqual(next.month, 10)
        XCTAssertEqual(next.year, 2026)
    }

    /// The reason this lives in the service: incrementing 12 in a view gives 13.
    func testDecemberRollsIntoJanuaryOfTheNextYear() throws {
        let december = try MonthlyPlanService.createPlan(
            month: 12, year: 2026, startingBalance: dec("100"), protectedAmount: .zero,
            context: context
        )
        let next = MonthlyPlanService.nextMonth(after: december)
        XCTAssertEqual(next.month, 1)
        XCTAssertEqual(next.year, 2027)
    }

    func testEveryMonthAdvancesCorrectly() throws {
        for month in 1...12 {
            let plan = try MonthlyPlanService.createPlan(
                month: month, year: 2026, startingBalance: .zero, protectedAmount: .zero,
                context: context
            )
            let next = MonthlyPlanService.nextMonth(after: plan)
            if month == 12 {
                XCTAssertEqual(next.month, 1)
                XCTAssertEqual(next.year, 2027)
            } else {
                XCTAssertEqual(next.month, month + 1)
                XCTAssertEqual(next.year, 2026)
            }
        }
    }

    // MARK: - Rollover defaults

    func testRolloverCarriesWhatIsLeftAndTheProtectedAmount() throws {
        let plan = try makeSeptember()
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("700"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("624"), date: date(4), merchant: "Various",
            note: nil, category: category, plan: plan, context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100"), date: date(15), source: "Refund",
            note: nil, plan: plan, context: context
        )

        let defaults = MonthlyPlanService.rolloverDefaults(from: plan)
        XCTAssertEqual(defaults.month, 10)
        XCTAssertEqual(defaults.year, 2026)
        XCTAssertEqual(defaults.startingBalance, dec("1876"), "2400 + 100 - 624")
        XCTAssertEqual(defaults.protectedAmount, dec("1000"))
        XCTAssertEqual(defaults.previousMoneyRemaining, dec("1876"))
        XCTAssertFalse(defaults.startingBalanceWasClamped)
        XCTAssertEqual(defaults.categoryCount, 1)
    }

    /// A MonthlyPlan cannot hold a negative balance, so an overspent month
    /// starts the next at zero -- but the real figure has to survive so the UI
    /// can explain the adjustment instead of hiding it.
    func testNegativeRemainingClampsToZeroButIsStillReported() throws {
        let plan = try makeSeptember(starting: "500", protected: "0")
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("1000"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("625"), date: date(4), merchant: "Various",
            note: nil, category: category, plan: plan, context: context
        )

        let defaults = MonthlyPlanService.rolloverDefaults(from: plan)
        XCTAssertEqual(defaults.previousMoneyRemaining, dec("-125"),
                       "The negative result must not be lost")
        XCTAssertEqual(defaults.startingBalance, 0, "Starting money cannot be negative")
        XCTAssertTrue(defaults.startingBalanceWasClamped)
    }

    // MARK: - Creating the next month

    func testCreatesTheNextMonthAndCopiesCategories() throws {
        let september = try makeSeptember()
        let groceries = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: dec("300"), type: .flexible,
            plan: september, context: context
        )
        let rent = try BudgetCategoryService.createCategory(
            name: "Rent", monthlyBudget: dec("1200"), type: .fixed,
            plan: september, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("50"), date: date(4), merchant: "Fry's",
            note: nil, category: groceries, plan: september, context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100"), date: date(15), source: "Refund",
            note: nil, plan: september, context: context
        )

        let october = try MonthlyPlanService.createNextPlan(
            from: september,
            startingBalance: dec("1876"), protectedAmount: dec("1000"),
            copyCategories: true, context: context
        )

        XCTAssertEqual(october.monthKey, "2026-10")
        XCTAssertEqual(october.categories.count, 2)

        let names = october.categories.map(\.name).sorted()
        XCTAssertEqual(names, ["Groceries", "Rent"])

        let octoberGroceries = try XCTUnwrap(october.categories.first { $0.name == "Groceries" })
        let octoberRent = try XCTUnwrap(october.categories.first { $0.name == "Rent" })
        XCTAssertEqual(octoberGroceries.monthlyBudget, dec("300"))
        XCTAssertEqual(octoberRent.monthlyBudget, dec("1200"))
        XCTAssertEqual(octoberGroceries.type, .flexible)
        XCTAssertEqual(octoberRent.type, .fixed)

        // New objects, not shared ones.
        XCTAssertNotEqual(octoberGroceries.id, groceries.id)
        XCTAssertNotEqual(octoberRent.id, rent.id)
        XCTAssertEqual(octoberGroceries.plan?.id, october.id)
        XCTAssertEqual(groceries.plan?.id, september.id,
                       "September's category was moved instead of copied")

        // A new month starts empty.
        XCTAssertTrue(october.expenses.isEmpty, "Expenses were copied into the new month")
        XCTAssertTrue(october.moneyAdded.isEmpty, "Money Added was copied into the new month")
        XCTAssertTrue(octoberGroceries.expenses.isEmpty)
        XCTAssertEqual(FinanceCalculator.totalSpent(for: october), 0)
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: october), 0)

        // September is untouched.
        XCTAssertEqual(september.expenses.count, 1)
        XCTAssertEqual(september.moneyAdded.count, 1)
        XCTAssertEqual(september.categories.count, 2)
        XCTAssertEqual(FinanceCalculator.spent(in: groceries), dec("50"))
    }

    func testCreatingTheNextMonthWithoutCopyingCategories() throws {
        let september = try makeSeptember()
        try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: dec("300"), type: .flexible,
            plan: september, context: context
        )

        let october = try MonthlyPlanService.createNextPlan(
            from: september, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: false, context: context
        )

        XCTAssertEqual(october.categories.count, 0)
        XCTAssertEqual(september.categories.count, 1, "September lost a category")
    }

    func testCreatingAnAlreadyExistingNextMonthIsRejectedWithoutOverwriting() throws {
        let september = try makeSeptember()
        let october = try MonthlyPlanService.createNextPlan(
            from: september, startingBalance: dec("1876"), protectedAmount: dec("1000"),
            copyCategories: false, context: context
        )

        XCTAssertThrowsError(
            try MonthlyPlanService.createNextPlan(
                from: september, startingBalance: dec("5"), protectedAmount: .zero,
                copyCategories: false, context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError, .planAlreadyExists(month: 10, year: 2026)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 2)
        XCTAssertEqual(october.startingBalance, dec("1876"),
                       "The existing October was overwritten")
    }

    /// A failed rollover must leave nothing behind, not a month with some of
    /// its budgets.
    func testAFailedRolloverLeavesNoPartialMonth() throws {
        let september = try makeSeptember()
        for name in ["Groceries", "Rent", "Gym"] {
            try BudgetCategoryService.createCategory(
                name: name, monthlyBudget: dec("100"), type: .flexible,
                plan: september, context: context
            )
        }
        // October already exists, so the rollover is refused before anything is
        // inserted.
        try MonthlyPlanService.createNextPlan(
            from: september, startingBalance: .zero, protectedAmount: .zero,
            copyCategories: false, context: context
        )

        XCTAssertThrowsError(
            try MonthlyPlanService.createNextPlan(
                from: september, startingBalance: .zero, protectedAmount: .zero,
                copyCategories: true, context: context
            )
        )

        let october = try XCTUnwrap(
            try MonthlyPlanService.existingPlan(month: 10, year: 2026, context: context)
        )
        XCTAssertEqual(october.categories.count, 0,
                       "A rejected rollover copied categories anyway")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 2)
    }

    // MARK: - Month selection

    func testSelectionPrefersTheChosenMonthThenTheNewest() throws {
        let august = try MonthlyPlanService.createPlan(
            month: 8, year: 2026, startingBalance: dec("1"), protectedAmount: .zero,
            context: context
        )
        let september = try makeSeptember()
        let plans = [september, august]

        let selection = MonthSelection()
        selection.monthKey = "2026-08"
        XCTAssertEqual(selection.resolvePlan(from: plans)?.id, august.id)

        selection.monthKey = "2026-09"
        XCTAssertEqual(selection.resolvePlan(from: plans)?.id, september.id)

        // An unknown key falls back rather than showing nothing.
        selection.monthKey = "1999-01"
        XCTAssertNotNil(selection.resolvePlan(from: plans))

        selection.monthKey = nil
        XCTAssertNotNil(selection.resolvePlan(from: plans))
        XCTAssertNil(selection.resolvePlan(from: []))
    }
}
