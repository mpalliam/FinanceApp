import XCTest
import SwiftData
@testable import FinanceNotebook

final class ExpenseServiceTests: XCTestCase {

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
            month: 9, year: 2026,
            startingBalance: Decimal(string: "2400.00")!,
            protectedAmount: Decimal(string: "1000.00")!,
            context: context
        )
        eatingOut = try BudgetCategoryService.createCategory(
            name: "Eating Out",
            monthlyBudget: Decimal(string: "200.00")!,
            type: .flexible,
            plan: plan,
            context: context
        )
    }

    override func tearDown() {
        eatingOut = nil
        plan = nil
        context = nil
        container = nil
    }

    private func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeChipotle(
        amount: Decimal = Decimal(string: "14.72")!,
        merchant: String = "Chipotle",
        note: String? = nil,
        category: BudgetCategory? = nil,
        on day: Int = 4
    ) throws -> Expense {
        try ExpenseService.createExpense(
            amount: amount,
            date: date(day),
            merchant: merchant,
            note: note,
            category: category ?? eatingOut,
            plan: plan,
            context: context
        )
    }

    private func expenseCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Expense>())
    }

    // MARK: - Creation

    func testCreatesValidExpense() throws {
        let expense = try makeChipotle()

        XCTAssertEqual(expense.amount, Decimal(string: "14.72")!)
        XCTAssertEqual(expense.merchant, "Chipotle")
        XCTAssertEqual(expense.category?.name, "Eating Out")
        XCTAssertEqual(expense.plan?.monthKey, "2026-09")
        XCTAssertEqual(expense.date, date(4))
        XCTAssertNil(expense.note)
        XCTAssertEqual(try expenseCount(), 1)
    }

    func testExpenseIsReachableFromBothParents() throws {
        let expense = try makeChipotle()
        XCTAssertTrue(plan.expenses.contains { $0.id == expense.id })
        XCTAssertTrue(eatingOut.expenses.contains { $0.id == expense.id })
    }

    func testMerchantAndNoteAreTrimmed() throws {
        let expense = try makeChipotle(merchant: "  Chipotle  ", note: "  Dinner after class  ")
        XCTAssertEqual(expense.merchant, "Chipotle")
        XCTAssertEqual(expense.note, "Dinner after class")
    }

    func testWhitespaceOnlyNoteBecomesNil() throws {
        let expense = try makeChipotle(note: "   \n  ")
        XCTAssertNil(expense.note)
    }

    // MARK: - Validation

    func testRejectsZeroAmount() throws {
        XCTAssertThrowsError(try makeChipotle(amount: 0)) { error in
            XCTAssertEqual(error as? ExpenseError, .amountNotPositive)
        }
        XCTAssertEqual(try expenseCount(), 0)
    }

    func testRejectsNegativeAmount() throws {
        XCTAssertThrowsError(try makeChipotle(amount: Decimal(string: "-14.72")!)) { error in
            XCTAssertEqual(error as? ExpenseError, .amountNotPositive)
        }
        XCTAssertEqual(try expenseCount(), 0)
    }

    func testRejectsBlankMerchant() throws {
        XCTAssertThrowsError(try makeChipotle(merchant: "")) { error in
            XCTAssertEqual(error as? ExpenseError, .blankMerchant)
        }
        XCTAssertEqual(try expenseCount(), 0)
    }

    func testRejectsWhitespaceOnlyMerchant() throws {
        XCTAssertThrowsError(try makeChipotle(merchant: "   \t \n ")) { error in
            XCTAssertEqual(error as? ExpenseError, .blankMerchant)
        }
        XCTAssertEqual(try expenseCount(), 0)
    }

    func testRejectsMissingCategory() throws {
        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: 10, date: date(4), merchant: "Chipotle",
                note: nil, category: nil, plan: plan, context: context
            )
        ) { error in
            XCTAssertEqual(error as? ExpenseError, .missingCategory)
        }
        XCTAssertEqual(try expenseCount(), 0)
    }

    func testRejectsDateOutsideThePlansMonth() throws {
        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: 10, date: date(15, 10, 2026), merchant: "Chipotle",
                note: nil, category: eatingOut, plan: plan, context: context
            )
        ) { error in
            XCTAssertEqual(
                error as? ExpenseError,
                .dateOutsidePlanMonth(monthTitle: plan.displayTitle)
            )
        }
    }

    func testRejectsDateInAnEarlierYear() throws {
        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: 10, date: date(4, 9, 2025), merchant: "Chipotle",
                note: nil, category: eatingOut, plan: plan, context: context
            )
        ) { error in
            XCTAssertEqual(
                error as? ExpenseError,
                .dateOutsidePlanMonth(monthTitle: plan.displayTitle)
            )
        }
    }

    func testRejectsCategoryBelongingToAnotherMonth() throws {
        let october = try MonthlyPlanService.createPlan(
            month: 10, year: 2026, startingBalance: 500, protectedAmount: 0, context: context
        )
        let octoberCategory = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: 150, type: .flexible,
            plan: october, context: context
        )

        XCTAssertThrowsError(try makeChipotle(category: octoberCategory)) { error in
            XCTAssertEqual(error as? ExpenseError, .categoryFromAnotherMonth)
        }
        XCTAssertEqual(try expenseCount(), 0)
    }

    func testValidExpenseStillSucceedsAfterRejections() throws {
        XCTAssertThrowsError(try makeChipotle(amount: 0))
        XCTAssertThrowsError(try makeChipotle(merchant: " "))
        let expense = try makeChipotle()
        XCTAssertEqual(expense.merchant, "Chipotle")
        XCTAssertEqual(try expenseCount(), 1)
    }

    // MARK: - Editing

    func testEditingUpdatesInPlaceWithoutCreatingADuplicate() throws {
        let expense = try makeChipotle()
        let originalID = expense.id
        let originalCreatedAt = expense.createdAt

        try ExpenseService.updateExpense(
            expense,
            amount: Decimal(string: "18.25")!,
            date: expense.date,
            merchant: "Chipotle",
            note: "Dinner with friends",
            category: eatingOut,
            context: context
        )

        XCTAssertEqual(try expenseCount(), 1, "Editing created a second expense")
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(stored.id, originalID, "The expense lost its identity")
        XCTAssertEqual(stored.createdAt, originalCreatedAt)
        XCTAssertEqual(stored.amount, Decimal(string: "18.25")!)
        XCTAssertEqual(stored.note, "Dinner with friends")
    }

    func testEditingCanChangeCategory() throws {
        let expense = try makeChipotle()
        let groceries = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: 300, type: .flexible,
            plan: plan, context: context
        )

        try ExpenseService.updateExpense(
            expense,
            amount: expense.amount, date: expense.date, merchant: expense.merchant,
            note: nil, category: groceries, context: context
        )

        XCTAssertEqual(expense.category?.name, "Groceries")
        XCTAssertTrue(groceries.expenses.contains { $0.id == expense.id })
        XCTAssertFalse(eatingOut.expenses.contains { $0.id == expense.id })
        XCTAssertEqual(try expenseCount(), 1)
    }

    func testEditingAppliesTheSameValidationRules() throws {
        let expense = try makeChipotle()

        XCTAssertThrowsError(
            try ExpenseService.updateExpense(
                expense, amount: 0, date: expense.date, merchant: "Chipotle",
                note: nil, category: eatingOut, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError, .amountNotPositive) }

        XCTAssertThrowsError(
            try ExpenseService.updateExpense(
                expense, amount: 5, date: expense.date, merchant: "   ",
                note: nil, category: eatingOut, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError, .blankMerchant) }

        XCTAssertThrowsError(
            try ExpenseService.updateExpense(
                expense, amount: 5, date: date(15, 10, 2026), merchant: "Chipotle",
                note: nil, category: eatingOut, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError, .dateOutsidePlanMonth(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(expense.amount, Decimal(string: "14.72")!,
                       "A rejected edit must not have changed the expense")
    }

    // MARK: - Deleting

    func testDeletingRemovesOnlyThatExpense() throws {
        let chipotle = try makeChipotle()
        let target = try makeChipotle(amount: Decimal(string: "32.49")!, merchant: "Target", on: 5)

        try ExpenseService.deleteExpense(chipotle, context: context)

        let remaining = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, target.id)
    }

    func testDeletingAnExpenseLeavesItsCategoryAndPlanIntact() throws {
        let expense = try makeChipotle()

        try ExpenseService.deleteExpense(expense, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1,
                       "Deleting an expense deleted its category")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1,
                       "Deleting an expense deleted its month")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 0)
        XCTAssertTrue(plan.expenses.isEmpty)
        XCTAssertTrue(eatingOut.expenses.isEmpty)
    }
}
