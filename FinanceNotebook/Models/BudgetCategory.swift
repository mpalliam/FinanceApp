import Foundation
import SwiftData

/// Whether a category's spending is essentially the same every month (Fixed)
/// or varies with day-to-day choices (Flexible).
enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case fixed
    case flexible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixed: "Fixed"
        case .flexible: "Flexible"
        }
    }
}

/// A spending budget within one month. Categories are per-month, so the same
/// name in two different months is two separate objects with their own budgets.
@Model
final class BudgetCategory {

    @Attribute(.unique) var id: UUID = UUID()

    var name: String = ""
    var monthlyBudget: Decimal = Decimal.zero
    var type: CategoryType = CategoryType.flexible

    var plan: MonthlyPlan?

    // Nullify, never cascade. Deleting a category must not delete the record of
    // money that was actually spent -- those expenses survive with no category
    // and still count against the month's total.
    @Relationship(deleteRule: .nullify, inverse: \Expense.category)
    var expenses: [Expense] = []

    init(
        name: String,
        monthlyBudget: Decimal,
        type: CategoryType,
        plan: MonthlyPlan? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.monthlyBudget = monthlyBudget
        self.type = type
        self.plan = plan
    }
}
