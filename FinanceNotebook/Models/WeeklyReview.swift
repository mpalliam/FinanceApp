import Foundation
import SwiftData

/// A short check-in part-way through a month.
///
/// The financial numbers a review is looking at are never stored here. They are
/// recomputed from the ledger whenever the review is opened, so an old review
/// cannot end up disagreeing with the records it was written about. Only the
/// user's own words are persisted.
///
/// The link to `plan` is deliberately one-directional: MonthlyPlan has no
/// `weeklyReviews` array. Adding one would change MonthlyPlan, which
/// FinanceNotebookSchemaV1 still describes, and V1 must keep describing the
/// schema as it actually was.
@Model
final class WeeklyReview {

    @Attribute(.unique) var id: UUID = UUID()

    /// The first day of the week this review covers, normalised by
    /// `ReviewService.weekStart(for:)`. One review per plan per week.
    var weekStartDate: Date = Date()

    var note: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var plan: MonthlyPlan?

    init(weekStartDate: Date, note: String? = nil, plan: MonthlyPlan? = nil) {
        let now = Date()
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.note = note
        self.plan = plan
        self.createdAt = now
        self.updatedAt = now
    }
}
