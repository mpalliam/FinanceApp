import Foundation
import SwiftData

enum ExpenseError: Error, Equatable {

    case amountNotPositive
    case blankMerchant
    case missingCategory

    /// The chosen category belongs to a different month's plan.
    case categoryFromAnotherMonth

    /// The date falls outside the month the expense belongs to.
    case dateOutsidePlanMonth(monthTitle: String)

    /// The expense is not attached to a month at all.
    case missingPlan

    /// The month has been closed and is read-only.
    case planIsClosed(monthTitle: String)

    /// A bulk reassignment was given expenses from more than one month.
    case mixedPlans
}

extension ExpenseError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .amountNotPositive:
            "Enter an amount greater than zero."
        case .blankMerchant:
            "Enter where you spent the money."
        case .missingCategory:
            "Choose a category for this expense."
        case .categoryFromAnotherMonth:
            "That category belongs to a different month."
        case .dateOutsidePlanMonth(let monthTitle):
            "Pick a date in \(monthTitle). This expense belongs to that month."
        case .missingPlan:
            "This expense is not attached to a month."
        case .planIsClosed(let monthTitle):
            "\(monthTitle) is closed. Expenses cannot be changed in a closed month."
        case .mixedPlans:
            "Those expenses belong to different months and cannot be changed together."
        }
    }
}

/// All expense writes go through here so that the same validation applies
/// wherever an expense is created or changed, and so views stay free of rules.
enum ExpenseService {

    // MARK: - Create

    @discardableResult
    static func createExpense(
        amount: Decimal,
        date: Date,
        merchant: String,
        note: String?,
        category: BudgetCategory?,
        plan: MonthlyPlan,
        context: ModelContext
    ) throws -> Expense {

        try requireOpen(plan)

        let clean = try validate(
            amount: amount, date: date, merchant: merchant,
            note: note, category: category, plan: plan
        )

        let expense = Expense(
            amount: amount,
            date: date,
            merchant: clean.merchant,
            note: clean.note,
            category: category,
            plan: plan
        )
        context.insert(expense)
        try context.save()
        return expense
    }

    // MARK: - Update

    /// Edits the expense in place. Deliberately not delete-and-recreate: the
    /// object keeps its identity, its id and its createdAt.
    static func updateExpense(
        _ expense: Expense,
        amount: Decimal,
        date: Date,
        merchant: String,
        note: String?,
        category: BudgetCategory?,
        context: ModelContext
    ) throws {

        guard let plan = expense.plan else { throw ExpenseError.missingPlan }
        try requireOpen(plan)

        let clean = try validate(
            amount: amount, date: date, merchant: merchant,
            note: note, category: category, plan: plan
        )

        expense.amount = abs(amount)
        expense.date = date
        expense.merchant = clean.merchant
        expense.note = clean.note
        expense.category = category

        try context.save()
    }

    // MARK: - Bulk reassignment

    /// Moves several expenses into one category at once.
    ///
    /// Built for cleaning up after a deleted category, where doing it one
    /// expense at a time is tedious enough that it does not get done.
    ///
    /// Only the category changes. Amount, date, merchant, note, month and -- most
    /// importantly -- the expense's id are all left alone, so this is a
    /// reassignment rather than a rewrite. That also means the month's totals
    /// cannot move: the same money is still spent, just filed differently.
    ///
    /// Everything is checked before anything is written, and the whole set is
    /// committed by a single save, so a rejected reassignment leaves every
    /// expense exactly as it was rather than changing some of them.
    ///
    /// An empty selection is a no-op rather than an error: nothing was asked
    /// for, so nothing happens and nothing is saved.
    @discardableResult
    static func assignCategory(
        to expenses: [Expense],
        category: BudgetCategory,
        context: ModelContext
    ) throws -> Int {

        guard !expenses.isEmpty else { return 0 }

        // Every expense must belong to one month, and it must be the category's
        // month. Filing September's spending under an October budget would
        // quietly corrupt both months' figures.
        guard let categoryPlan = category.plan else {
            throw ExpenseError.missingPlan
        }
        var plans = Set<UUID>()
        for expense in expenses {
            guard let plan = expense.plan else { throw ExpenseError.missingPlan }
            plans.insert(plan.id)
        }
        guard plans.count == 1 else { throw ExpenseError.mixedPlans }
        guard plans.first == categoryPlan.id else {
            throw ExpenseError.categoryFromAnotherMonth
        }

        try requireOpen(categoryPlan)

        // Nothing above wrote anything, so a throw leaves the store untouched.
        for expense in expenses {
            expense.category = category
        }
        try context.save()
        return expenses.count
    }

    // MARK: - Delete

    static func deleteExpense(_ expense: Expense, context: ModelContext) throws {
        if let plan = expense.plan { try requireOpen(plan) }
        context.delete(expense)
        try context.save()
    }

    // MARK: - Closure

    /// A closed month is history. Nothing may be added to, changed in, or
    /// removed from it, whatever route the caller took to get here.
    private static func requireOpen(_ plan: MonthlyPlan) throws {
        guard !plan.isClosed else {
            throw ExpenseError.planIsClosed(monthTitle: plan.displayTitle)
        }
    }

    // MARK: - Validation

    /// Returns the cleaned text values, or throws the first rule broken.
    @discardableResult
    static func validate(
        amount: Decimal,
        date: Date,
        merchant: String,
        note: String?,
        category: BudgetCategory?,
        plan: MonthlyPlan
    ) throws -> (merchant: String, note: String?) {

        guard amount > 0 else { throw ExpenseError.amountNotPositive }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else { throw ExpenseError.blankMerchant }

        guard let category else { throw ExpenseError.missingCategory }
        guard category.plan?.id == plan.id else { throw ExpenseError.categoryFromAnotherMonth }

        guard plan.contains(date) else {
            throw ExpenseError.dateOutsidePlanMonth(monthTitle: plan.displayTitle)
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedMerchant, (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote)
    }
}
