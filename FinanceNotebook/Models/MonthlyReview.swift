import Foundation
import SwiftData

/// The end-of-month reflection. At most one per month.
///
/// As with WeeklyReview, no financial totals are stored: the month summary
/// shown alongside these answers is derived from the ledger every time.
///
/// The link to `plan` is one-directional for the same reason -- MonthlyPlan
/// must stay exactly as FinanceNotebookSchemaV1 describes it.
@Model
final class MonthlyReview {

    @Attribute(.unique) var id: UUID = UUID()

    /// Did I spend more than I expected?
    var spentMoreThanExpected: String?

    /// Was there a purchase I regret or could have avoided?
    var avoidablePurchase: String?

    /// What purchase felt worthwhile?
    var worthwhilePurchase: String?

    /// What should I change next month?
    var changeNextMonth: String?

    /// Anything else I want to remember?
    var additionalNotes: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var plan: MonthlyPlan?

    init(plan: MonthlyPlan? = nil) {
        let now = Date()
        self.id = UUID()
        self.plan = plan
        self.createdAt = now
        self.updatedAt = now
    }

    /// True when the user has actually written something. Used so that merely
    /// opening the form does not leave an empty record behind.
    var hasContent: Bool {
        [spentMoreThanExpected, avoidablePurchase, worthwhilePurchase,
         changeNextMonth, additionalNotes]
            .contains { ($0?.isEmpty == false) }
    }
}
