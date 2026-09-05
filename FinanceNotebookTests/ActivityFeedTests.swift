import XCTest
import SwiftData
@testable import FinanceNotebook

/// Home's recent activity list, derived in memory from the records that exist.
final class ActivityFeedTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!
    private var category: BudgetCategory!

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
            name: "Eating Out", monthlyBudget: dec("500"), type: .flexible,
            plan: plan, context: context
        )
    }

    override func tearDown() {
        category = nil; plan = nil; context = nil; container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    @discardableResult
    private func addExpense(_ amount: String, _ merchant: String, on day: Int) throws -> Expense {
        try ExpenseService.createExpense(
            amount: dec(amount), date: date(day), merchant: merchant,
            note: nil, category: category, plan: plan, context: context
        )
    }

    @discardableResult
    private func addMoney(_ amount: String, _ source: String, on day: Int) throws -> MoneyAddedEntry {
        try MoneyAddedService.createEntry(
            amount: dec(amount), date: date(day), source: source,
            note: nil, plan: plan, context: context
        )
    }

    func testCombinesExpensesAndMoneyAddedNewestFirst() throws {
        try addExpense("25", "Target", on: 10)
        try addMoney("100", "Refund", on: 12)
        try addExpense("15", "Chipotle", on: 14)

        let activity = ActivityFeed.activity(for: plan)

        XCTAssertEqual(activity.map(\.title), ["Chipotle", "Refund", "Target"])
        XCTAssertEqual(activity.map(\.kind), [.expense, .moneyAdded, .expense])
    }

    func testSignsAreDisplayOnlyAndTheStoredAmountStaysPositive() throws {
        let expense = try addExpense("14.72", "Chipotle", on: 4)
        let entry = try addMoney("100", "Refund", on: 5)

        let activity = ActivityFeed.activity(for: plan)
        let expenseItem = try XCTUnwrap(activity.first { $0.kind == .expense })
        let moneyItem = try XCTUnwrap(activity.first { $0.kind == .moneyAdded })

        XCTAssertTrue(expenseItem.displayAmount.hasPrefix("-"),
                      "Expense should read as money going out: \(expenseItem.displayAmount)")
        XCTAssertTrue(moneyItem.displayAmount.hasPrefix("+"),
                      "Money Added should read as money coming in: \(moneyItem.displayAmount)")
        XCTAssertFalse(expenseItem.displayAmount.contains("$-"))
        XCTAssertFalse(moneyItem.displayAmount.contains("$+"))

        XCTAssertEqual(expense.amount, dec("14.72"), "The stored amount was changed")
        XCTAssertEqual(entry.amount, dec("100"))
        XCTAssertEqual(expenseItem.amount, dec("14.72"))
    }

    func testSubtitlesNameTheCategoryOrTheKind() throws {
        try addExpense("10", "Chipotle", on: 4)
        try addMoney("50", "Refund", on: 5)

        let activity = ActivityFeed.activity(for: plan)
        XCTAssertEqual(activity.first { $0.title == "Chipotle" }?.subtitle, "Eating Out")
        XCTAssertEqual(activity.first { $0.title == "Refund" }?.subtitle, "Money Added")
    }

    func testUncategorizedExpensesStillAppear() throws {
        let temp = try BudgetCategoryService.createCategory(
            name: "Temp", monthlyBudget: .zero, type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("30"), date: date(6), merchant: "Orphan",
            note: nil, category: temp, plan: plan, context: context
        )
        try BudgetCategoryService.deleteCategory(temp, context: context)

        let activity = ActivityFeed.activity(for: plan)
        XCTAssertEqual(activity.first { $0.title == "Orphan" }?.subtitle, "Uncategorized")
    }

    func testLimitReturnsOnlyTheMostRecent() throws {
        for day in 1...10 {
            try addExpense("\(day)", "Day\(day)", on: day)
        }

        let limited = ActivityFeed.activity(for: plan, limit: 5)
        XCTAssertEqual(limited.count, 5)
        XCTAssertEqual(limited.map(\.title), ["Day10", "Day9", "Day8", "Day7", "Day6"])
        XCTAssertEqual(ActivityFeed.activity(for: plan).count, 10, "The limit is display-only")
    }

    /// Same-day records must keep a stable order rather than shuffling.
    func testSameDayRecordsAreOrderedStably() throws {
        try addExpense("10", "First", on: 8)
        try addExpense("20", "Second", on: 8)
        try addMoney("30", "Third", on: 8)

        let first = ActivityFeed.activity(for: plan).map(\.title)
        let second = ActivityFeed.activity(for: plan).map(\.title)
        XCTAssertEqual(first, second, "The order changed between two identical reads")
        XCTAssertEqual(Set(first), ["First", "Second", "Third"])
        XCTAssertEqual(first.first, "Third", "The newest record on the day should lead")
    }

    func testEmptyMonthHasNoActivity() throws {
        XCTAssertTrue(ActivityFeed.activity(for: plan).isEmpty)
        XCTAssertTrue(ActivityFeed.activity(for: plan, limit: 5).isEmpty)
    }

    func testActivityBelongsOnlyToItsOwnMonth() throws {
        try addExpense("10", "September", on: 4)
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: true, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("20"), date: Calendar.current.date(
                from: DateComponents(year: 2026, month: 10, day: 3))!,
            merchant: "October", note: nil,
            category: october.categories.first, plan: october, context: context
        )

        XCTAssertEqual(ActivityFeed.activity(for: plan).map(\.title), ["September"])
        XCTAssertEqual(ActivityFeed.activity(for: october).map(\.title), ["October"])
    }
}
