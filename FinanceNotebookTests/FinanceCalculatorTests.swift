import XCTest
import SwiftData
@testable import FinanceNotebook

final class FinanceCalculatorTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400"), protectedAmount: dec("1000"),
            context: context
        )
    }

    override func tearDown() {
        plan = nil
        context = nil
        container = nil
    }

    // MARK: - Fixtures

    private func dec(_ value: String) -> Decimal { Decimal(string: value)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    @discardableResult
    private func category(_ name: String, budget: String,
                          type: CategoryType = .flexible) throws -> BudgetCategory {
        try BudgetCategoryService.createCategory(
            name: name, monthlyBudget: dec(budget), type: type, plan: plan, context: context
        )
    }

    @discardableResult
    private func expense(_ amount: String, in category: BudgetCategory?,
                         merchant: String = "M", day: Int = 4) throws -> Expense {
        try ExpenseService.createExpense(
            amount: dec(amount), date: date(day), merchant: merchant,
            note: nil, category: category, plan: plan, context: context
        )
    }

    /// Uncategorized expenses cannot be created through ExpenseService, which
    /// requires a category. They only arise when a category is deleted, so this
    /// reproduces that route rather than faking the state.
    private func makeUncategorizedExpense(_ amount: String) throws {
        let temp = try category("Temp", budget: "0")
        try expense(amount, in: temp, merchant: "Orphan")
        try BudgetCategoryService.deleteCategory(temp, context: context)
    }

    private func moneyAdded(_ amount: String, source: String = "Refund") throws {
        let entry = MoneyAddedEntry(
            amount: dec(amount), date: date(15), source: source, plan: plan
        )
        context.insert(entry)
        try context.save()
    }

    // MARK: - Monthly totals

    func testEmptyMonth() throws {
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), 0)
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2400"))
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), 0)
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("2400"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1400"))
    }

    func testNormalSpending() throws {
        let eatingOut = try category("Eating Out", budget: "1000")
        try expense("600", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("600"))
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("1800"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("800"))
    }

    func testMoneyAddedIncreasesTotalMoneyAndSafeToSpend() throws {
        let eatingOut = try category("Eating Out", budget: "1000")
        try expense("600", in: eatingOut)
        try moneyAdded("100")

        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("100"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2500"))
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("1900"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("900"))
    }

    func testMultipleMoneyAddedEntriesAreSummed() throws {
        try moneyAdded("100", source: "Refund")
        try moneyAdded("50.25", source: "Reimbursement")
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("150.25"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2550.25"))
    }

    /// Safe to Spend must be allowed to go negative: that is the warning.
    func testSafeToSpendGoesNegativeWhenProtectedMoneyIsEatenInto() throws {
        let eatingOut = try category("Eating Out", budget: "2000")
        try expense("1500", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("900"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("-100"))
        XCTAssertTrue(FinanceCalculator.summary(for: plan).isProtectedMoneyAtRisk)
    }

    /// Protected money is not spending. Money Remaining must not subtract it.
    func testMoneyRemainingDoesNotSubtractProtectedMoney() throws {
        let eatingOut = try category("Eating Out", budget: "1000")
        try expense("600", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("1800"))
        XCTAssertNotEqual(FinanceCalculator.moneyRemaining(for: plan), dec("800"),
                          "Money Remaining wrongly subtracted the protected amount")
    }

    // MARK: - Decimal precision

    func testMultipleExpensesSumExactly() throws {
        let groceries = try category("Groceries", budget: "500")
        try expense("14.72", in: groceries, merchant: "Chipotle", day: 2)
        try expense("63.27", in: groceries, merchant: "Fry's", day: 3)
        try expense("41.18", in: groceries, merchant: "Shell", day: 4)

        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("119.17"))
    }

    func testSmallDecimalsDoNotDrift() throws {
        let misc = try category("Misc", budget: "10")
        for _ in 0..<10 {
            try expense("0.01", in: misc)
        }
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("0.10"),
                       "Ten cents did not sum exactly; this is what Decimal prevents")
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("2399.90"))
    }

    // MARK: - Uncategorized

    func testUncategorizedExpensesStillCountTowardTheMonth() throws {
        let groceries = try category("Groceries", budget: "300")
        try expense("50", in: groceries, merchant: "Fry's")
        try makeUncategorizedExpense("25")

        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("75"),
                       "The uncategorized expense vanished from total spending")
        XCTAssertEqual(FinanceCalculator.spent(in: groceries), dec("50"))
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: plan), dec("25"))
        XCTAssertEqual(FinanceCalculator.uncategorizedExpenses(for: plan).count, 1)
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("2325"))
    }

    // MARK: - Category totals

    func testUnderBudget() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("150", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("150"))
        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), dec("50"))
        XCTAssertFalse(FinanceCalculator.isOverBudget(eatingOut))
        XCTAssertEqual(FinanceCalculator.progress(for: eatingOut), dec("0.75"))
    }

    func testExactlyOnBudget() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("200", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), 0)
        XCTAssertFalse(FinanceCalculator.isOverBudget(eatingOut),
                       "Spending exactly the budget is not over budget")
        XCTAssertEqual(FinanceCalculator.progress(for: eatingOut), 1)
        XCTAssertEqual(FinanceCalculator.displayProgress(for: eatingOut), 1.0, accuracy: 0.0001)
    }

    func testOverBudget() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("215", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), dec("-15"))
        XCTAssertTrue(FinanceCalculator.isOverBudget(eatingOut))
    }

    /// The raw fraction is not clamped; only the bar is.
    func testOverspendingReportsMoreThanOneHundredPercent() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("250", in: eatingOut)

        XCTAssertEqual(FinanceCalculator.progress(for: eatingOut), dec("1.25"),
                       "The financial calculation must not be clamped")
        XCTAssertEqual(FinanceCalculator.displayProgress(for: eatingOut), 1.0, accuracy: 0.0001,
                       "The progress bar value must be clamped to 1")
        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), dec("-50"))
    }

    func testZeroBudgetWithNoSpendingDoesNotDivideByZero() throws {
        let misc = try category("Misc", budget: "0")

        XCTAssertNil(FinanceCalculator.progress(for: misc),
                     "A zero budget has no meaningful fraction")
        XCTAssertEqual(FinanceCalculator.displayProgress(for: misc), 0.0, accuracy: 0.0001)
        XCTAssertEqual(FinanceCalculator.remaining(in: misc), 0)
        XCTAssertFalse(FinanceCalculator.isOverBudget(misc))
    }

    func testZeroBudgetWithSpendingIsEntirelyOverBudget() throws {
        let misc = try category("Misc", budget: "0")
        try expense("30", in: misc)

        XCTAssertNil(FinanceCalculator.progress(for: misc))
        XCTAssertEqual(FinanceCalculator.displayProgress(for: misc), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FinanceCalculator.remaining(in: misc), dec("-30"))
        XCTAssertTrue(FinanceCalculator.isOverBudget(misc))
    }

    func testCategoryTotalsAreIndependentOfEachOther() throws {
        let groceries = try category("Groceries", budget: "300")
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("214", in: groceries, merchant: "Fry's")
        try expense("167", in: eatingOut, merchant: "Chipotle")

        XCTAssertEqual(FinanceCalculator.spent(in: groceries), dec("214"))
        XCTAssertEqual(FinanceCalculator.remaining(in: groceries), dec("86"))
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("167"))
        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), dec("33"))
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("381"))
    }

    /// Fixed and Flexible use the same arithmetic for now.
    func testFixedAndFlexibleCategoriesCalculateIdentically() throws {
        let gym = try category("Gym", budget: "50", type: .fixed)
        let fun = try category("Fun", budget: "50", type: .flexible)
        try expense("20", in: gym)
        try expense("20", in: fun)

        XCTAssertEqual(FinanceCalculator.remaining(in: gym),
                       FinanceCalculator.remaining(in: fun))
        XCTAssertEqual(FinanceCalculator.progress(for: gym),
                       FinanceCalculator.progress(for: fun))
    }

    // MARK: - The worked example from the milestone

    func testTheWorkedExample() throws {
        let groceries = try category("Groceries", budget: "700")
        try expense("624", in: groceries)
        try moneyAdded("100")

        let summary = FinanceCalculator.summary(for: plan)
        XCTAssertEqual(summary.startingBalance, dec("2400"))
        XCTAssertEqual(summary.moneyAdded, dec("100"))
        XCTAssertEqual(summary.totalMoney, dec("2500"))
        XCTAssertEqual(summary.totalSpent, dec("624"))
        XCTAssertEqual(summary.moneyRemaining, dec("1876"))
        XCTAssertEqual(summary.protectedAmount, dec("1000"))
        XCTAssertEqual(summary.safeToSpend, dec("876"))
        XCTAssertFalse(summary.isProtectedMoneyAtRisk)
    }

    // MARK: - Recalculation, not caching

    /// Totals must follow the records. Nothing is stored, so nothing can go stale.
    func testTotalsFollowAddEditAndDelete() throws {
        let eatingOut = try category("Eating Out", budget: "500")
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1400"))

        let chipotle = try expense("100", in: eatingOut, merchant: "Chipotle")
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1300"))

        try ExpenseService.updateExpense(
            chipotle, amount: dec("150"), date: chipotle.date, merchant: "Chipotle",
            note: nil, category: eatingOut, context: context
        )
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1250"))
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("150"))

        try ExpenseService.deleteExpense(chipotle, context: context)
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1400"))
        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), 0)
    }

    func testEditingACategoryBudgetChangesRemainingImmediately() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("150", in: eatingOut)
        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), dec("50"))

        try BudgetCategoryService.updateCategory(
            eatingOut, name: "Eating Out", monthlyBudget: dec("250"),
            type: .flexible, context: context
        )
        XCTAssertEqual(FinanceCalculator.remaining(in: eatingOut), dec("100"))
    }

    func testChangingAnExpensesCategoryMovesTheSpending() throws {
        let groceries = try category("Groceries", budget: "300")
        let eatingOut = try category("Eating Out", budget: "200")
        let chipotle = try expense("40", in: eatingOut, merchant: "Chipotle")

        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), dec("40"))
        XCTAssertEqual(FinanceCalculator.spent(in: groceries), 0)

        try ExpenseService.updateExpense(
            chipotle, amount: chipotle.amount, date: chipotle.date,
            merchant: chipotle.merchant, note: nil, category: groceries, context: context
        )

        XCTAssertEqual(FinanceCalculator.spent(in: eatingOut), 0)
        XCTAssertEqual(FinanceCalculator.spent(in: groceries), dec("40"))
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("40"),
                       "Moving an expense must not change the month's total")
    }

    // MARK: - Negative presentation

    func testNegativeAmountsFormatWithTheMinusOutsideTheSymbol() {
        let text = dec("-75").currencyText
        XCTAssertFalse(text.contains("$-"), "Malformed negative currency: \(text)")
        XCTAssertTrue(text.contains("75"))
    }
}

/// The "near limit" rule reviews use to decide which budgets are worth
/// mentioning. Threshold is 80% of the budget.
final class CategoryAttentionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: Decimal(string: "5000")!, protectedAmount: .zero,
            context: context
        )
    }

    override func tearDown() {
        plan = nil; context = nil; container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func category(_ name: String, budget: String, spent: String)
        throws -> BudgetCategory {
        let category = try BudgetCategoryService.createCategory(
            name: name, monthlyBudget: dec(budget), type: .flexible,
            plan: plan, context: context
        )
        if dec(spent) > 0 {
            try ExpenseService.createExpense(
                amount: dec(spent),
                date: Calendar.current.date(
                    from: DateComponents(year: 2026, month: 9, day: 4))!,
                merchant: name, note: nil, category: category,
                plan: plan, context: context
            )
        }
        return category
    }

    func testJustUnderTheThresholdIsNotNearLimit() throws {
        let category = try category("Eating Out", budget: "200", spent: "159")
        XCTAssertFalse(FinanceCalculator.needsAttention(category),
                       "159 of 200 is 79.5%, below the 80% threshold")
    }

    func testExactlyAtTheThresholdIsNearLimit() throws {
        let category = try category("Eating Out", budget: "200", spent: "160")
        XCTAssertTrue(FinanceCalculator.needsAttention(category),
                      "160 of 200 is exactly 80%")
    }

    func testOverBudgetIsAlwaysNearLimit() throws {
        let category = try category("Eating Out", budget: "200", spent: "215")
        XCTAssertTrue(FinanceCalculator.needsAttention(category))
        XCTAssertTrue(FinanceCalculator.isOverBudget(category))
    }

    /// Zero budget with spending needs attention; without, it does not, and
    /// neither case may divide by zero.
    func testZeroBudgetWithSpendingNeedsAttention() throws {
        let spending = try category("Misc", budget: "0", spent: "20")
        XCTAssertTrue(FinanceCalculator.needsAttention(spending))
        XCTAssertNil(FinanceCalculator.progress(for: spending))
    }

    func testZeroBudgetWithoutSpendingDoesNotNeedAttention() throws {
        let untouched = try category("Gym", budget: "0", spent: "0")
        XCTAssertFalse(FinanceCalculator.needsAttention(untouched),
                       "An untouched zero-budget category is not near anything")
        XCTAssertNil(FinanceCalculator.progress(for: untouched))
    }

    func testAnUntouchedBudgetDoesNotNeedAttention() throws {
        let category = try category("Gym", budget: "100", spent: "0")
        XCTAssertFalse(FinanceCalculator.needsAttention(category))
    }

    func testTheListIsFilteredAndOrderedBySpending() throws {
        try category("Fine", budget: "500", spent: "10")
        try category("Close", budget: "200", spent: "180")
        try category("Over", budget: "100", spent: "150")

        let flagged = FinanceCalculator.categoriesNeedingAttention(for: plan)
        XCTAssertEqual(flagged.map(\.name), ["Close", "Over"],
                       "Expected only the two at risk, most spent first")
    }
}
