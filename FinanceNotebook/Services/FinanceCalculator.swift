import Foundation

/// Every money total the app shows is derived here, from the records that are
/// actually persisted. Nothing in this file is stored.
///
/// That is deliberate. A stored `totalSpent` would be one bad save away from
/// disagreeing with the expenses it claims to summarise, and a wrong number
/// that looks authoritative is worse than no number. Recomputing from the
/// ledger cannot drift.
///
/// Everything stays in `Decimal`. The only conversion to `Double` is
/// `displayProgress`, which feeds a progress bar and never a money value.
enum FinanceCalculator {

    // MARK: - Monthly totals

    /// Sum of every MoneyAddedEntry in the month. Zero when there are none.
    static func moneyAdded(for plan: MonthlyPlan) -> Decimal {
        plan.moneyAdded.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// startingBalance + moneyAdded
    static func totalMoney(for plan: MonthlyPlan) -> Decimal {
        plan.startingBalance + moneyAdded(for: plan)
    }

    /// Sum of every expense in the month, including uncategorized ones.
    ///
    /// Expenses are stored positive, so this is a plain sum.
    static func totalSpent(for plan: MonthlyPlan) -> Decimal {
        plan.expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// totalMoney - totalSpent
    ///
    /// Protected money is NOT subtracted here. It was never spent or moved; it
    /// is still money the user has.
    static func moneyRemaining(for plan: MonthlyPlan) -> Decimal {
        totalMoney(for: plan) - totalSpent(for: plan)
    }

    /// moneyRemaining - protectedAmount
    ///
    /// Allowed to go negative, and never clamped: a negative number is the
    /// whole point, because it says the user has started spending money they
    /// meant to protect.
    static func safeToSpend(for plan: MonthlyPlan) -> Decimal {
        moneyRemaining(for: plan) - plan.protectedAmount
    }

    // MARK: - Category totals

    /// Sum of the expenses assigned to this category.
    static func spent(in category: BudgetCategory) -> Decimal {
        category.expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// monthlyBudget - categorySpent. Negative means over budget.
    static func remaining(in category: BudgetCategory) -> Decimal {
        category.monthlyBudget - spent(in: category)
    }

    static func isOverBudget(_ category: BudgetCategory) -> Bool {
        spent(in: category) > category.monthlyBudget
    }

    /// How much of the budget has been used, as a fraction.
    ///
    /// `nil` when the category has no budget to measure against, rather than a
    /// made-up 0 or 1 — with a zero budget the question has no answer, and the
    /// caller has to decide what to show.
    ///
    /// Not clamped: 250 spent against a 200 budget really is 1.25.
    static func progress(for category: BudgetCategory) -> Decimal? {
        let budget = category.monthlyBudget
        guard budget > 0 else { return nil }
        return spent(in: category) / budget
    }

    /// A 0...1 value for a progress bar only.
    ///
    /// This is the one place a money-derived number becomes a Double, and it
    /// is the one place clamping is correct: the bar cannot draw past full.
    /// The financial figures beside it stay exact and unclamped.
    static func displayProgress(for category: BudgetCategory) -> Double {
        guard let fraction = progress(for: category) else {
            // No budget: either nothing has happened, or everything spent is
            // over budget.
            return spent(in: category) > 0 ? 1 : 0
        }
        let value = NSDecimalNumber(decimal: fraction).doubleValue
        return min(max(value, 0), 1)
    }

    // MARK: - Attention

    /// A category is worth mentioning in a review once it has used this much of
    /// its budget. 80% is a deliberate, documented choice, not a tuned number:
    /// it is late enough to matter and early enough to still act on.
    static let attentionThreshold = Decimal(string: "0.8")!

    /// Whether a category deserves a mention in a weekly check-in.
    ///
    /// Over budget always counts. A category with no budget counts only once
    /// something has been spent against it -- an untouched zero-budget category
    /// is not "near" anything, and asking about it would be noise.
    static func needsAttention(_ category: BudgetCategory) -> Bool {
        if isOverBudget(category) { return true }
        guard let fraction = progress(for: category) else {
            return spent(in: category) > 0
        }
        return fraction >= attentionThreshold
    }

    /// The month's categories that deserve attention, most used first.
    static func categoriesNeedingAttention(for plan: MonthlyPlan) -> [BudgetCategory] {
        plan.categories
            .filter(needsAttention)
            .sorted { spent(in: $0) > spent(in: $1) }
    }

    // MARK: - Uncategorized

    /// Expenses whose category was deleted. They keep counting toward the
    /// month, they just belong to no budget.
    static func uncategorizedExpenses(for plan: MonthlyPlan) -> [Expense] {
        plan.expenses.filter { $0.category == nil }
    }

    static func uncategorizedSpent(for plan: MonthlyPlan) -> Decimal {
        uncategorizedExpenses(for: plan).reduce(Decimal.zero) { $0 + $1.amount }
    }

    // MARK: - Composed summary

    /// The month's figures in one value, for screens that show several at once.
    /// Composed from the functions above; the arithmetic is not repeated.
    static func summary(for plan: MonthlyPlan) -> MonthlySummary {
        MonthlySummary(
            startingBalance: plan.startingBalance,
            moneyAdded: moneyAdded(for: plan),
            totalMoney: totalMoney(for: plan),
            totalSpent: totalSpent(for: plan),
            moneyRemaining: moneyRemaining(for: plan),
            protectedAmount: plan.protectedAmount,
            safeToSpend: safeToSpend(for: plan)
        )
    }
}

struct MonthlySummary: Equatable {
    let startingBalance: Decimal
    let moneyAdded: Decimal
    let totalMoney: Decimal
    let totalSpent: Decimal
    let moneyRemaining: Decimal
    let protectedAmount: Decimal
    let safeToSpend: Decimal

    /// True once spending has eaten into money the user meant to protect.
    var isProtectedMoneyAtRisk: Bool { safeToSpend < 0 }
}
