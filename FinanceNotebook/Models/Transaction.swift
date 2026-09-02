import Foundation
import SwiftData

/// An expense. For V1 a Transaction is always money going out.
///
/// The link to `plan` is deliberately kept alongside the link to `category`
/// rather than being reached through it: because deleting a category nullifies
/// `category`, month membership has to be stored independently or an expense
/// would silently drop out of its month's totals.
@Model
final class Transaction {

    @Attribute(.unique) var id: UUID = UUID()

    /// Always positive. Expenses are not represented as negative numbers.
    var amount: Decimal = Decimal.zero

    var date: Date = Date()
    var merchant: String = ""
    var note: String?
    var createdAt: Date = Date()

    /// Optional so that deleting a category leaves the expense uncategorized
    /// instead of destroying it.
    var category: BudgetCategory?

    var plan: MonthlyPlan?

    init(
        amount: Decimal,
        date: Date,
        merchant: String,
        note: String? = nil,
        category: BudgetCategory? = nil,
        plan: MonthlyPlan? = nil
    ) {
        self.id = UUID()
        self.amount = abs(amount)
        self.date = date
        self.merchant = merchant
        self.note = note
        self.category = category
        self.plan = plan
        self.createdAt = Date()
    }
}
