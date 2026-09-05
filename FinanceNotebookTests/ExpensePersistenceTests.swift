import XCTest
import SwiftData
@testable import FinanceNotebook

/// Expense add / edit / delete against a real on-disk store, with the container
/// fully released between each write and the check that follows it.
final class ExpensePersistenceTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appending(path: "FinanceNotebook-expense-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }
        storeURL = nil
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        )
    }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    /// Creates September 2026 + Eating Out + a $14.72 Chipotle expense, then
    /// closes the store.
    private func seedAndClose() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: Decimal(string: "2400.00")!,
            protectedAmount: Decimal(string: "1000.00")!,
            context: context
        )
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: Decimal(string: "200.00")!,
            type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: Decimal(string: "14.72")!, date: date(4), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: context
        )
    }

    func testCreatedExpenseSurvivesAStoreReopen() throws {
        try seedAndClose()

        let container = try makeContainer()
        let context = ModelContext(container)

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 1)
        let expense = try XCTUnwrap(expenses.first)

        XCTAssertEqual(expense.merchant, "Chipotle")
        XCTAssertEqual(expense.amount, Decimal(string: "14.72")!)
        XCTAssertEqual(expense.category?.name, "Eating Out",
                       "Expense -> BudgetCategory did not survive")
        XCTAssertEqual(expense.plan?.monthKey, "2026-09",
                       "Expense -> MonthlyPlan did not survive")
        XCTAssertEqual(expense.date, date(4))
    }

    func testEditedAmountAndNoteSurviveAStoreReopen() throws {
        try seedAndClose()

        var originalID: UUID!
        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let expense = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
            originalID = expense.id

            try ExpenseService.updateExpense(
                expense,
                amount: Decimal(string: "18.25")!,
                date: expense.date,
                merchant: "Chipotle",
                note: "Dinner with friends",
                category: expense.category,
                context: context
            )
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let expenses = try context.fetch(FetchDescriptor<Expense>())

        XCTAssertEqual(expenses.count, 1, "Editing produced a duplicate on disk")
        let expense = try XCTUnwrap(expenses.first)
        XCTAssertEqual(expense.id, originalID, "The edited expense lost its identity")
        XCTAssertEqual(expense.amount, Decimal(string: "18.25")!)
        XCTAssertEqual(expense.note, "Dinner with friends")
        XCTAssertEqual(expense.category?.name, "Eating Out")
    }

    func testDeletedExpenseStaysDeletedAndLeavesItsParentsIntact() throws {
        try seedAndClose()

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let expense = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
            try ExpenseService.deleteExpense(expense, context: context)
        }

        let container = try makeContainer()
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 0,
                       "The deleted expense came back")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1,
                       "Deleting an expense took its category with it")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1,
                       "Deleting an expense took its month with it")
    }
}
