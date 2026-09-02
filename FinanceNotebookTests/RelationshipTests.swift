import XCTest
import SwiftData
@testable import FinanceNotebook

/// The rename must not have altered the delete rules: a month owns its records,
/// but a category does not own the money spent against it.
final class RelationshipTests: XCTestCase {

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

    private func makeFixture() throws -> (MonthlyPlan, BudgetCategory, Expense) {
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )
        let category = BudgetCategory(
            name: "Eating Out", monthlyBudget: 200, type: .flexible, plan: plan
        )
        context.insert(category)

        let expense = Expense(
            amount: Decimal(string: "14.72")!, date: Date(),
            merchant: "Chipotle", category: category, plan: plan
        )
        context.insert(expense)
        try context.save()

        return (plan, category, expense)
    }

    func testExpenseIsReachableFromBothParents() throws {
        let (plan, category, expense) = try makeFixture()

        XCTAssertEqual(plan.expenses.count, 1)
        XCTAssertEqual(category.expenses.count, 1)
        XCTAssertEqual(expense.plan?.id, plan.id)
        XCTAssertEqual(expense.category?.id, category.id)
    }

    /// The important one: deleting a category must NOT delete spending history.
    func testDeletingCategoryNullifiesItsExpensesRatherThanDeletingThem() throws {
        let (plan, category, _) = try makeFixture()

        context.delete(category)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(remaining.count, 1, "Deleting a category destroyed an expense")
        XCTAssertNil(remaining.first?.category, "Expense should be uncategorized")
        XCTAssertEqual(remaining.first?.plan?.id, plan.id,
                       "Expense must still belong to its month")
        XCTAssertEqual(remaining.first?.merchant, "Chipotle")
    }

    /// Deleting a month is deliberately destructive for that month only.
    func testDeletingPlanCascadesToItsChildren() throws {
        let (plan, _, _) = try makeFixture()

        let entry = MoneyAddedEntry(amount: 100, date: Date(), source: "Refund", plan: plan)
        context.insert(entry)
        try context.save()

        context.delete(plan)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 0)
    }

    /// Deleting one month must not touch another month's records.
    func testDeletingOnePlanLeavesAnotherMonthIntact() throws {
        let (september, _, _) = try makeFixture()

        let october = try MonthlyPlanService.createPlan(
            month: 10, year: 2026, startingBalance: 500, protectedAmount: 0, context: context
        )
        let octoberCategory = BudgetCategory(
            name: "Groceries", monthlyBudget: 150, type: .flexible, plan: october
        )
        context.insert(octoberCategory)
        context.insert(Expense(amount: 32, date: Date(), merchant: "Safeway",
                               category: octoberCategory, plan: october))
        try context.save()

        context.delete(september)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1)
        let survivingExpenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(survivingExpenses.count, 1)
        XCTAssertEqual(survivingExpenses.first?.merchant, "Safeway")
    }

    func testExpenseAmountIsStoredPositive() throws {
        let expense = Expense(amount: -25, date: Date(), merchant: "Refunded typo")
        context.insert(expense)
        try context.save()

        XCTAssertEqual(expense.amount, 25, "Expenses must never be stored negative")
    }
}
