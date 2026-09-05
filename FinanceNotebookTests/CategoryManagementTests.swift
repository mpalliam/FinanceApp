import XCTest
import SwiftData
@testable import FinanceNotebook

/// Editing and deleting categories, with the emphasis on what must NOT happen
/// to the expenses attached to them.
final class CategoryManagementTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV1.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: Decimal(string: "2400")!,
            protectedAmount: Decimal(string: "1000")!,
            context: context
        )
    }

    override func tearDown() {
        plan = nil
        context = nil
        container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    private func makeEatingOutWithExpenses() throws -> BudgetCategory {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"),
            type: .flexible, plan: plan, context: context
        )
        for (index, amount) in ["14.72", "22.10", "31.00"].enumerated() {
            try ExpenseService.createExpense(
                amount: dec(amount), date: date(index + 1), merchant: "Merchant\(index)",
                note: nil, category: category, plan: plan, context: context
            )
        }
        return category
    }

    // MARK: - Editing

    func testRenamingKeepsTheSameCategoryAndItsExpenses() throws {
        let category = try makeEatingOutWithExpenses()
        let originalID = category.id
        let spentBefore = FinanceCalculator.spent(in: category)

        try BudgetCategoryService.updateCategory(
            category, name: "Dining Out", monthlyBudget: dec("250"),
            type: .flexible, context: context
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1,
                       "Editing created a second category")

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<BudgetCategory>()).first)
        XCTAssertEqual(stored.id, originalID, "The category lost its identity")
        XCTAssertEqual(stored.name, "Dining Out")
        XCTAssertEqual(stored.monthlyBudget, dec("250"))
        XCTAssertEqual(stored.expenses.count, 3, "Expenses were detached by the rename")
        XCTAssertEqual(FinanceCalculator.spent(in: stored), spentBefore)
        XCTAssertEqual(FinanceCalculator.remaining(in: stored), dec("182.18"))
    }

    func testEditingCanChangeType() throws {
        let category = try makeEatingOutWithExpenses()
        try BudgetCategoryService.updateCategory(
            category, name: category.name, monthlyBudget: category.monthlyBudget,
            type: .fixed, context: context
        )
        XCTAssertEqual(category.type, .fixed)
        XCTAssertEqual(category.expenses.count, 3)
    }

    func testEditingTrimsAndRejectsBadInput() throws {
        let category = try makeEatingOutWithExpenses()

        try BudgetCategoryService.updateCategory(
            category, name: "  Dining Out  ", monthlyBudget: dec("250"),
            type: .flexible, context: context
        )
        XCTAssertEqual(category.name, "Dining Out")

        XCTAssertThrowsError(
            try BudgetCategoryService.updateCategory(
                category, name: "   ", monthlyBudget: dec("250"),
                type: .flexible, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError, .blankName) }

        XCTAssertThrowsError(
            try BudgetCategoryService.updateCategory(
                category, name: "Dining Out", monthlyBudget: dec("-1"),
                type: .flexible, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError, .negativeBudget) }

        XCTAssertEqual(category.name, "Dining Out", "A rejected edit changed the category")
        XCTAssertEqual(category.monthlyBudget, dec("250"))
    }

    // MARK: - Deleting

    func testDeletingACategoryKeepsItsExpensesAndTheirSpending() throws {
        let category = try makeEatingOutWithExpenses()
        let totalBefore = FinanceCalculator.totalSpent(for: plan)
        XCTAssertEqual(totalBefore, dec("67.82"))

        try BudgetCategoryService.deleteCategory(category, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 0,
                       "The category was not deleted")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 3,
                       "Deleting a category destroyed financial history")

        for expense in try context.fetch(FetchDescriptor<Expense>()) {
            XCTAssertNil(expense.category, "Expense should be uncategorized")
            XCTAssertEqual(expense.plan?.id, plan.id, "Expense lost its month")
        }

        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), totalBefore,
                       "Total spending changed when a category was deleted")
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: plan), totalBefore)
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("2332.18"))
    }

    func testDeletingAnEmptyCategoryLeavesOtherCategoriesAlone() throws {
        let eatingOut = try makeEatingOutWithExpenses()
        let empty = try BudgetCategoryService.createCategory(
            name: "Gym", monthlyBudget: dec("50"), type: .fixed, plan: plan, context: context
        )

        try BudgetCategoryService.deleteCategory(empty, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1)
        XCTAssertEqual(eatingOut.expenses.count, 3)
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("67.82"))
    }

    func testDeletingOneCategoryDoesNotTouchAnothersExpenses() throws {
        let eatingOut = try makeEatingOutWithExpenses()
        let groceries = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: dec("300"),
            type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("63.27"), date: date(5), merchant: "Fry's",
            note: nil, category: groceries, plan: plan, context: context
        )

        try BudgetCategoryService.deleteCategory(eatingOut, context: context)

        XCTAssertEqual(groceries.expenses.count, 1)
        XCTAssertEqual(FinanceCalculator.spent(in: groceries), dec("63.27"))
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: plan), dec("67.82"))
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("131.09"))
    }

    /// §18: an expense left uncategorized must be re-assignable through the
    /// normal edit path, without any schema change.
    func testAnUncategorizedExpenseCanBeGivenACategoryAgain() throws {
        let eatingOut = try makeEatingOutWithExpenses()
        try BudgetCategoryService.deleteCategory(eatingOut, context: context)

        let groceries = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: dec("300"),
            type: .flexible, plan: plan, context: context
        )
        let orphan = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertNil(orphan.category)

        try ExpenseService.updateExpense(
            orphan, amount: orphan.amount, date: orphan.date, merchant: orphan.merchant,
            note: nil, category: groceries, context: context
        )

        XCTAssertEqual(orphan.category?.id, groceries.id)
        XCTAssertEqual(FinanceCalculator.spent(in: groceries), orphan.amount)
        XCTAssertEqual(FinanceCalculator.uncategorizedExpenses(for: plan).count, 2)
    }

    // MARK: - Editing the month's money

    func testUpdatingStartingAndProtectedMoney() throws {
        try MonthlyPlanService.updateMoney(
            plan, startingBalance: dec("2500"), protectedAmount: dec("1200"), context: context
        )

        XCTAssertEqual(plan.startingBalance, dec("2500"))
        XCTAssertEqual(plan.protectedAmount, dec("1200"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1300"))
    }

    func testUpdatingMoneyRejectsNegativeValuesAndChangesNothing() throws {
        XCTAssertThrowsError(
            try MonthlyPlanService.updateMoney(
                plan, startingBalance: dec("-1"), protectedAmount: dec("1000"), context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError, .negativeStartingBalance) }

        XCTAssertThrowsError(
            try MonthlyPlanService.updateMoney(
                plan, startingBalance: dec("2400"), protectedAmount: dec("-1"), context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError, .negativeProtectedAmount) }

        XCTAssertEqual(plan.startingBalance, dec("2400"))
        XCTAssertEqual(plan.protectedAmount, dec("1000"))
    }

    /// Money added later in the month can make this legitimate.
    func testProtectedMoneyMayExceedStartingMoney() throws {
        try MonthlyPlanService.updateMoney(
            plan, startingBalance: dec("100"), protectedAmount: dec("500"), context: context
        )
        XCTAssertEqual(plan.protectedAmount, dec("500"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("-400"))
    }

    /// Editing money must not disturb the month's identity.
    func testUpdatingMoneyLeavesMonthYearAndKeyUntouched() throws {
        try MonthlyPlanService.updateMoney(
            plan, startingBalance: dec("2500"), protectedAmount: dec("1200"), context: context
        )
        XCTAssertEqual(plan.month, 9)
        XCTAssertEqual(plan.year, 2026)
        XCTAssertEqual(plan.monthKey, "2026-09")
    }
}
