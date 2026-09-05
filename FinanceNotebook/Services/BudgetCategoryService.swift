import Foundation
import SwiftData

enum BudgetCategoryError: Error, Equatable {
    case blankName
    case negativeBudget
}

extension BudgetCategoryError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .blankName:
            "Enter a name for this category."
        case .negativeBudget:
            "A monthly budget cannot be negative."
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
        context.delete(category)
        try context.save()
    }
}
