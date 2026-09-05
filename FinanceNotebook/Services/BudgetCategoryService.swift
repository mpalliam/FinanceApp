import Foundation
import SwiftData

enum BudgetCategoryError: Error, Equatable {
    case blankName
    case negativeBudget

    /// The month has been closed and is read-only.
    case planIsClosed(monthTitle: String)

    /// The category is not attached to a month at all.
    case missingPlan
}

extension BudgetCategoryError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .blankName:
            "Enter a name for this category."
        case .negativeBudget:
            "A monthly budget cannot be negative."
        case .planIsClosed(let monthTitle):
            "\(monthTitle) is closed. Categories cannot be changed in a closed month."
        case .missingPlan:
            "This category is not attached to a month."
        }
    }
}

/// Minimal for now: expense entry needs categories to exist, so this creates
/// them. The full budgeting interface comes later.
enum BudgetCategoryService {

    @discardableResult
    static func createCategory(
        name: String,
        monthlyBudget: Decimal,
        type: CategoryType,
        plan: MonthlyPlan,
        context: ModelContext
    ) throws -> BudgetCategory {

        try requireOpen(plan)

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BudgetCategoryError.blankName }

        // Zero is allowed: a category can be tracked without a budget yet.
        guard monthlyBudget >= 0 else { throw BudgetCategoryError.negativeBudget }

        let category = BudgetCategory(
            name: trimmed,
            monthlyBudget: monthlyBudget,
            type: type,
            plan: plan
        )
        context.insert(category)
        try context.save()
        return category
    }

    /// Edits the category in place, so the expenses already pointing at it stay
    /// pointing at it. Renaming is not a reason to build a new category.
    static func updateCategory(
        _ category: BudgetCategory,
        name: String,
        monthlyBudget: Decimal,
        type: CategoryType,
        context: ModelContext
    ) throws {
        guard let plan = category.plan else { throw BudgetCategoryError.missingPlan }
        try requireOpen(plan)

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BudgetCategoryError.blankName }
        guard monthlyBudget >= 0 else { throw BudgetCategoryError.negativeBudget }

        category.name = trimmed
        category.monthlyBudget = monthlyBudget
        category.type = type

        try context.save()
    }

    /// Deletes the category. Its expenses are NOT deleted: the relationship's
    /// nullify rule leaves them in place with no category, so the money still
    /// counts toward the month. Callers must say so before asking to confirm.
    static func deleteCategory(_ category: BudgetCategory, context: ModelContext) throws {
        if let plan = category.plan { try requireOpen(plan) }
        context.delete(category)
        try context.save()
    }

    /// A closed month is history and does not accept changes.
    private static func requireOpen(_ plan: MonthlyPlan) throws {
        guard !plan.isClosed else {
            throw BudgetCategoryError.planIsClosed(monthTitle: plan.displayTitle)
        }
    }
}
