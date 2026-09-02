import Foundation
import SwiftData

/// Money that becomes available part-way through a month -- a refund, a
/// reimbursement, money from family, money from selling something.
///
/// This is intentionally not income: it does not recur and it is not a salary.
@Model
final class MoneyAddedEntry {

    @Attribute(.unique) var id: UUID = UUID()

    /// Always positive.
    var amount: Decimal = Decimal.zero

    var date: Date = Date()

    /// Where the money came from, e.g. "Refund".
    var source: String = ""

    var note: String?
    var createdAt: Date = Date()

    var plan: MonthlyPlan?

    init(
        amount: Decimal,
        date: Date,
        source: String,
        note: String? = nil,
        plan: MonthlyPlan? = nil
    ) {
        self.id = UUID()
        self.amount = abs(amount)
        self.date = date
        self.source = source
        self.note = note
        self.plan = plan
        self.createdAt = Date()
    }
}
