import XCTest
import SwiftData
@testable import FinanceNotebook

/// Bulk reassignment of expenses whose category was deleted.
///
/// The guarantee that matters is that this *files* money differently without
/// *changing* it: same expenses, same amounts, same ids, same month totals.
final class UncategorizedCleanupTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!
    private var eatingOut: BudgetCategory!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: dec("2400"),
            protectedAmount: dec("1000"), context: context
        )
        eatingOut = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"), type: .flexible,
            plan: plan, context: context
        )
    }

    override func tearDown() {
        eatingOut = nil; plan = nil; context = nil; container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int, _ month: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    /// Uncategorized expenses, created the way they actually occur: a category
    /// is deleted and the nullify rule leaves its spending behind.
    @discardableResult
    private func makeOrphans(_ amounts: [String]) throws -> [Expense] {
        let doomed = try BudgetCategoryService.createCategory(
            name: "Doomed \(UUID().uuidString.prefix(4))", monthlyBudget: .zero,
            type: .flexible, plan: plan, context: context
        )
        var made: [Expense] = []
        for (index, amount) in amounts.enumerated() {
            // Cycle within the month: an expense must be dated inside the plan
            // it belongs to, so a long list cannot just keep counting days up.
            made.append(
                try ExpenseService.createExpense(
                    amount: dec(amount), date: date((index % 28) + 1),
                    merchant: "Orphan \(index)", note: nil,
                    category: doomed, plan: plan, context: context
                )
            )
        }
        try BudgetCategoryService.deleteCategory(doomed, context: context)
        return made
    }

    // MARK: - Reassigning

    func testAssigningASingleExpense() throws {
        let orphans = try makeOrphans(["14.72"])
        let expense = try XCTUnwrap(orphans.first)
        XCTAssertNil(expense.category)

        let changed = try ExpenseService.assignCategory(
            to: [expense], category: eatingOut, context: context
        )

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(expense.category?.id, eatingOut.id)
        XCTAssertTrue(FinanceCalculator.uncategorizedExpenses(for: plan).isEmpty)
    }

    func testAssigningSeveralAtOnce() throws {
        let orphans = try makeOrphans(["10.00", "20.00", "30.00"])

        let changed = try ExpenseService.assignCategory(
            to: orphans, category: eatingOut, context: context
        )

        XCTAssertEqual(changed, 3)
        for expense in orphans {
            XCTAssertEqual(expense.category?.id, eatingOut.id)
        }
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("60.00"))
        XCTAssertTrue(FinanceCalculator.uncategorizedExpenses(for: plan).isEmpty)
    }

    /// Only what was selected moves.
    func testUnselectedExpensesAreUntouched() throws {
        let orphans = try makeOrphans(["10.00", "20.00", "30.00"])
        let chosen = [orphans[0], orphans[2]]

        try ExpenseService.assignCategory(to: chosen, category: eatingOut, context: context)

        XCTAssertEqual(orphans[0].category?.id, eatingOut.id)
        XCTAssertNil(orphans[1].category, "An unselected expense was reassigned")
        XCTAssertEqual(orphans[2].category?.id, eatingOut.id)
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: plan), dec("20.00"))
    }

    /// A reassignment is a reassignment, not a rewrite.
    func testEverythingExceptTheCategoryIsPreserved() throws {
        let doomed = try BudgetCategoryService.createCategory(
            name: "Doomed", monthlyBudget: .zero, type: .flexible,
            plan: plan, context: context
        )
        let expense = try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(3), merchant: "Chipotle",
            note: "Lunch after class", category: doomed, plan: plan, context: context
        )
        try BudgetCategoryService.deleteCategory(doomed, context: context)

        let id = expense.id
        let createdAt = expense.createdAt

        try ExpenseService.assignCategory(to: [expense], category: eatingOut, context: context)

        XCTAssertEqual(expense.id, id, "The expense lost its identity")
        XCTAssertEqual(expense.createdAt, createdAt, "A timestamp moved")
        XCTAssertEqual(expense.amount, dec("14.72"))
        XCTAssertEqual(expense.date, date(3))
        XCTAssertEqual(expense.merchant, "Chipotle")
        XCTAssertEqual(expense.note, "Lunch after class")
        XCTAssertEqual(expense.plan?.id, plan.id, "The expense changed month")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1,
                       "The expense was recreated rather than reassigned")
    }

    /// The month's money cannot move: the same amount is still spent.
    func testTheMonthsTotalsDoNotChange() throws {
        try ExpenseService.createExpense(
            amount: dec("50.00"), date: date(2), merchant: "Categorised",
            note: nil, category: eatingOut, plan: plan, context: context
        )
        let orphans = try makeOrphans(["10.00", "20.00"])

        let spentBefore = FinanceCalculator.totalSpent(for: plan)
        let remainingBefore = FinanceCalculator.moneyRemaining(for: plan)
        let safeBefore = FinanceCalculator.safeToSpend(for: plan)

        try ExpenseService.assignCategory(to: orphans, category: eatingOut, context: context)

        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), spentBefore,
                       "Reassigning changed what the month spent")
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), remainingBefore)
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), safeBefore)
    }

    /// The money moves between buckets even though the total does not.
    func testCategoryTotalsMoveAcross() throws {
        let orphans = try makeOrphans(["10.00", "20.00"])
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), 0)
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: plan), dec("30.00"))

        try ExpenseService.assignCategory(to: orphans, category: eatingOut, context: context)

        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("30.00"))
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: plan), 0)
    }

    // MARK: - Refusals

    /// A closed month is settled, and tidying it is still a financial change.
    func testAClosedMonthRefusesReassignment() throws {
        let orphans = try makeOrphans(["10.00", "20.00"])
        try MonthlyPlanService.closePlan(plan, context: context)

        XCTAssertThrowsError(
            try ExpenseService.assignCategory(to: orphans, category: eatingOut, context: context)
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        for expense in orphans {
            XCTAssertNil(expense.category, "A closed month was tidied anyway")
        }
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), 0)
    }

    /// September's spending must not be filed under an October budget.
    func testACategoryFromAnotherMonthIsRefused() throws {
        let orphans = try makeOrphans(["10.00"])
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: false, context: context
        )
        let octoberCategory = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: dec("300"), type: .flexible,
            plan: october, context: context
        )

        XCTAssertThrowsError(
            try ExpenseService.assignCategory(
                to: orphans, category: octoberCategory, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError, .categoryFromAnotherMonth) }

        XCTAssertNil(orphans[0].category, "A cross-month assignment went through")
        XCTAssertEqual(FinanceCalculator.spent(in: octoberCategory), 0)
    }

    /// Expenses from two months cannot be tidied together, and nothing partial
    /// happens when they are offered.
    func testAMixedSelectionIsRefusedWithoutPartialChanges() throws {
        let september = try makeOrphans(["10.00"])
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: false, context: context
        )
        let octoberDoomed = try BudgetCategoryService.createCategory(
            name: "Doomed", monthlyBudget: .zero, type: .flexible,
            plan: october, context: context
        )
        let octoberOrphan = try ExpenseService.createExpense(
            amount: dec("5.00"), date: date(3, 10), merchant: "October orphan",
            note: nil, category: octoberDoomed, plan: october, context: context
        )
        try BudgetCategoryService.deleteCategory(octoberDoomed, context: context)

        XCTAssertThrowsError(
            try ExpenseService.assignCategory(
                to: september + [octoberOrphan], category: eatingOut, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError, .mixedPlans) }

        XCTAssertNil(september[0].category, "A mixed selection partly went through")
        XCTAssertNil(octoberOrphan.category)
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), 0)
    }

    /// Nothing was asked for, so nothing happens.
    func testAnEmptySelectionIsANoOp() throws {
        let changed = try ExpenseService.assignCategory(
            to: [], category: eatingOut, context: context
        )
        XCTAssertEqual(changed, 0)
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), 0)
    }

    // MARK: - Scale

    /// A month's worth of cleanup in one operation, not one save per expense.
    func testAHundredExpensesReassignAtOnce() throws {
        let orphans = try makeOrphans((0..<100).map { _ in "1.00" })
        XCTAssertEqual(FinanceCalculator.uncategorizedExpenses(for: plan).count, 100)

        let changed = try ExpenseService.assignCategory(
            to: orphans, category: eatingOut, context: context
        )

        XCTAssertEqual(changed, 100)
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("100.00"))
        XCTAssertTrue(FinanceCalculator.uncategorizedExpenses(for: plan).isEmpty)
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("100.00"))
    }

    // MARK: - Persistence

    func testReassignmentSurvivesAStoreReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cleanup-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV2.self)
        func open() throws -> ModelContext {
            ModelContext(try ModelContainer(
                for: schema,
                migrationPlan: FinanceNotebookMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: url,
                                                    cloudKitDatabase: .none)]
            ))
        }

        var expenseID: UUID!
        var categoryID: UUID!
        do {
            let disk = try open()
            let diskPlan = try MonthlyPlanService.createPlan(
                month: 9, year: 2026, startingBalance: dec("2400"),
                protectedAmount: dec("1000"), context: disk
            )
            let target = try BudgetCategoryService.createCategory(
                name: "Eating Out", monthlyBudget: dec("200"), type: .flexible,
                plan: diskPlan, context: disk
            )
            categoryID = target.id
            let doomed = try BudgetCategoryService.createCategory(
                name: "Doomed", monthlyBudget: .zero, type: .flexible,
                plan: diskPlan, context: disk
            )
            let expense = try ExpenseService.createExpense(
                amount: dec("14.72"), date: date(3), merchant: "Chipotle",
                note: nil, category: doomed, plan: diskPlan, context: disk
            )
            expenseID = expense.id
            try BudgetCategoryService.deleteCategory(doomed, context: disk)
            try ExpenseService.assignCategory(to: [expense], category: target, context: disk)
        }

        let reopened = try open()
        let expense = try XCTUnwrap(
            try reopened.fetch(FetchDescriptor<Expense>()).first { $0.id == expenseID }
        )
        XCTAssertEqual(expense.category?.id, categoryID,
                       "The reassignment did not reach disk")
        XCTAssertEqual(expense.amount, dec("14.72"))
    }
}
