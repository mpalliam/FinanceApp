import Foundation
import SwiftData

/// One calendar month of money. A plan owns everything recorded inside it:
/// its budget categories, its expenses, and any money added during the month.
@Model
final class MonthlyPlan {

    @Attribute(.unique) var id: UUID = UUID()

    var month: Int = 1
    var year: Int = 2000

    /// Money available at the start of the month.
    var startingBalance: Decimal = Decimal.zero

    /// Money set aside that should not be spent.
    var protectedAmount: Decimal = Decimal.zero

    var isClosed: Bool = false
    var createdAt: Date = Date()

    // Cascade is safe on all three: categories, expenses and additions belong to
    // exactly one month and are never shared with another plan, so deleting a
    // plan cannot reach records that belong to a different month.

    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.plan)
    var categories: [BudgetCategory] = []

    @Relationship(deleteRule: .cascade, inverse: \Transaction.plan)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .cascade, inverse: \MoneyAddedEntry.plan)
    var moneyAdded: [MoneyAddedEntry] = []

    init(
        month: Int,
        year: Int,
        startingBalance: Decimal,
        protectedAmount: Decimal
    ) {
        self.id = UUID()
        self.month = month
        self.year = year
        self.startingBalance = startingBalance
        self.protectedAmount = protectedAmount
        self.isClosed = false
        self.createdAt = Date()
    }
}

extension MonthlyPlan {

    /// e.g. "September 2026"
    var displayTitle: String {
        var components = DateComponents()
        components.month = month
        components.year = year
        guard let date = Calendar.current.date(from: components) else {
            return "\(month)/\(year)"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
