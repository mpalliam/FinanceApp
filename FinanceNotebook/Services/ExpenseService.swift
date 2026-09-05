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

    // MARK: - Delete

    static func deleteExpense(_ expense: Expense, context: ModelContext) throws {
        context.delete(expense)
        try context.save()
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
