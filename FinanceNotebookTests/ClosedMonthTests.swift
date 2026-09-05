import XCTest
import SwiftData
@testable import FinanceNotebook

/// A closed month is finished history. It stays fully readable and its totals
/// still compute, but nothing may change it -- and that is enforced in the
/// services, not only in the UI, so no other route can quietly get around it.
final class ClosedMonthTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!
    private var category: BudgetCategory!
    private var expense: Expense!
    private var entry: MoneyAddedEntry!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV1.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)

        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400"), protectedAmount: dec("1000"),
            context: context
        )
        category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"), type: .flexible,
            plan: plan, context: context
        )
        expense = try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(4), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: context
        )
        entry = try MoneyAddedService.createEntry(
            amount: dec("100"), date: date(15), source: "Refund",
            note: nil, plan: plan, context: context
        )
    }

    override func tearDown() {
        entry = nil; expense = nil; category = nil; plan = nil
        context = nil; container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    private func close() throws {
        try MonthlyPlanService.closePlan(plan, context: context)
    }

    // MARK: - Closing

    func testClosingSetsTheFlag() throws {
        XCTAssertFalse(plan.isClosed)
        try close()
        XCTAssertTrue(plan.isClosed)
    }

    func testClosingIsIdempotent() throws {
        try close()
        try close()
        XCTAssertTrue(plan.isClosed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1)
    }

    /// The app records reality: an overspent or over-budget month can still be
    /// closed. Closing is not an approval.
    func testAMonthCanBeClosedWhileOverspent() throws {
        try ExpenseService.createExpense(
            amount: dec("5000"), date: date(20), merchant: "Disaster",
            note: nil, category: category, plan: plan, context: context
        )
        XCTAssertLessThan(FinanceCalculator.safeToSpend(for: plan), 0)
        XCTAssertTrue(FinanceCalculator.isOverBudget(category))

        try close()
        XCTAssertTrue(plan.isClosed)
    }

    /// Closing must not delete anything.
    func testClosingKeepsEveryRecordAndItsTotals() throws {
        let spentBefore = FinanceCalculator.totalSpent(for: plan)
        let summaryBefore = FinanceCalculator.summary(for: plan)

        try close()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 1)
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), spentBefore)
        XCTAssertEqual(FinanceCalculator.summary(for: plan), summaryBefore)
        XCTAssertEqual(FinanceCalculator.spent(in: category), dec("14.72"))
    }

    // MARK: - Expenses are frozen

    func testClosedMonthRejectsExpenseCreation() throws {
        try close()
        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: dec("10"), date: date(5), merchant: "Nope",
                note: nil, category: category, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1)
    }

    func testClosedMonthRejectsExpenseEditing() throws {
        try close()
        XCTAssertThrowsError(
            try ExpenseService.updateExpense(
                expense, amount: dec("99"), date: expense.date, merchant: "Changed",
                note: nil, category: category, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(expense.amount, dec("14.72"), "A rejected edit changed the expense")
        XCTAssertEqual(expense.merchant, "Chipotle")
    }

    /// A rejected write must not remove anything as a side effect.
    func testClosedMonthRejectsExpenseDeletionWithoutLosingIt() throws {
        try close()
        XCTAssertThrowsError(
            try ExpenseService.deleteExpense(expense, context: context)
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1)
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("14.72"))
    }

    // MARK: - Money Added is frozen

    func testClosedMonthRejectsMoneyAddedCreation() throws {
        try close()
        XCTAssertThrowsError(
            try MoneyAddedService.createEntry(
                amount: dec("10"), date: date(5), source: "Nope",
                note: nil, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 1)
    }

    func testClosedMonthRejectsMoneyAddedEditing() throws {
        try close()
        XCTAssertThrowsError(
            try MoneyAddedService.updateEntry(
                entry, amount: dec("999"), date: entry.date, source: "Changed",
                note: nil, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(entry.amount, dec("100"))
        XCTAssertEqual(entry.source, "Refund")
    }

    func testClosedMonthRejectsMoneyAddedDeletionWithoutLosingIt() throws {
        try close()
        XCTAssertThrowsError(
            try MoneyAddedService.deleteEntry(entry, context: context)
        ) { XCTAssertEqual($0 as? MoneyAddedError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 1)
    }

    // MARK: - Categories are frozen

    func testClosedMonthRejectsCategoryCreation() throws {
        try close()
        XCTAssertThrowsError(
            try BudgetCategoryService.createCategory(
                name: "Nope", monthlyBudget: dec("10"), type: .flexible,
                plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1)
    }

    func testClosedMonthRejectsCategoryEditing() throws {
        try close()
        XCTAssertThrowsError(
            try BudgetCategoryService.updateCategory(
                category, name: "Changed", monthlyBudget: dec("999"),
                type: .fixed, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(category.name, "Eating Out")
        XCTAssertEqual(category.monthlyBudget, dec("200"))
    }

    /// The most important one: a closed category deletion would orphan real
    /// expenses in a month that is supposed to be settled.
    func testClosedMonthRejectsCategoryDeletionWithoutOrphaningExpenses() throws {
        try close()
        XCTAssertThrowsError(
            try BudgetCategoryService.deleteCategory(category, context: context)
        ) { XCTAssertEqual($0 as? BudgetCategoryError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1)
        XCTAssertNotNil(expense.category, "The expense was orphaned by a rejected delete")
    }

    // MARK: - The month's own money is frozen

    func testClosedMonthRejectsMoneyEditing() throws {
        try close()
        XCTAssertThrowsError(
            try MonthlyPlanService.updateMoney(
                plan, startingBalance: dec("9999"), protectedAmount: .zero, context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(plan.startingBalance, dec("2400"))
        XCTAssertEqual(plan.protectedAmount, dec("1000"))
    }

    // MARK: - Other months keep working

    func testClosingOneMonthDoesNotFreezeAnother() throws {
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("1000"), protectedAmount: dec("500"),
            copyCategories: true, context: context
        )
        try close()

        let octoberCategory = try XCTUnwrap(october.categories.first)
        let newExpense = try ExpenseService.createExpense(
            amount: dec("20"), date: Calendar.current.date(
                from: DateComponents(year: 2026, month: 10, day: 3)
            )!,
            merchant: "Chipotle", note: nil,
            category: octoberCategory, plan: october, context: context
        )

        XCTAssertEqual(newExpense.plan?.monthKey, "2026-10")
        XCTAssertEqual(FinanceCalculator.totalSpent(for: october), dec("20"))
        XCTAssertTrue(plan.isClosed)
        XCTAssertFalse(october.isClosed)
    }

    /// Rollover reads the closed month but writes only the new one, so it is
    /// still allowed after closing.
    func testTheNextMonthCanStillBeStartedFromAClosedMonth() throws {
        try close()
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("1000"), protectedAmount: dec("500"),
            copyCategories: true, context: context
        )
        XCTAssertEqual(october.monthKey, "2026-10")
        XCTAssertEqual(october.categories.count, 1)
        XCTAssertFalse(october.isClosed)
    }
}
