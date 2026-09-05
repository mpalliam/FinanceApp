import Foundation
import SwiftData

enum ReviewError: Error, Equatable {
    case missingPlan
}

extension ReviewError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingPlan: "This review is not attached to a month."
        }
    }
}

/// Reviews are the user's own words about a month. They never change the
/// ledger, which is why a closed month still accepts them: closing settles the
/// money, not the reflection.
///
/// Nothing financial is stored on a review. Every number a review screen shows
/// is recomputed from the records through FinanceCalculator, so an old review
/// can never disagree with the month it describes.
enum ReviewService {

    // MARK: - Weeks

    /// The first day of the week containing `date`, at the start of that day.
    ///
    /// The single definition of a week boundary in the app. It follows the
    /// user's calendar, so the week starts on whichever day their locale says
    /// -- Sunday in the US, Monday in much of Europe -- rather than a day
    /// hardcoded here.
    ///
    /// A week can straddle two months. The review's month comes from the plan
    /// it belongs to, not from the week, so a check-in written on 1 October is
    /// October's even if its week began in September.
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: interval.start)
    }

    // MARK: - Weekly reviews

    /// The review for that plan and week, if one has been written.
    static func weeklyReview(
        for plan: MonthlyPlan,
        weekStart: Date,
        context: ModelContext
    ) throws -> WeeklyReview? {
        let planID = plan.id
        var descriptor = FetchDescriptor<WeeklyReview>(
            predicate: #Predicate { review in
                review.plan?.id == planID && review.weekStartDate == weekStart
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Every weekly review for a month, newest week first.
    static func weeklyReviews(
        for plan: MonthlyPlan,
        context: ModelContext
    ) throws -> [WeeklyReview] {
        let planID = plan.id
        let descriptor = FetchDescriptor<WeeklyReview>(
            predicate: #Predicate { $0.plan?.id == planID },
            sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Writes this week's note, creating the review only if there is something
    /// to say.
    ///
    /// Duplicates are prevented here rather than in the UI: an existing review
    /// for the same plan and week is updated, never joined by a second one. The
    /// week is normalised first, so two dates in the same week resolve to the
    /// same review.
    ///
    /// Returns nil when the note is blank and no review exists yet -- opening
    /// the form and closing it again should not leave an empty record behind.
    @discardableResult
    static func saveWeeklyReview(
        for plan: MonthlyPlan,
        weekStart: Date,
        note: String?,
        context: ModelContext
    ) throws -> WeeklyReview? {

        let normalisedWeek = self.weekStart(for: weekStart)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = (trimmed?.isEmpty ?? true) ? nil : trimmed

        if let existing = try weeklyReview(
            for: plan, weekStart: normalisedWeek, context: context
        ) {
            existing.note = cleanNote
            existing.updatedAt = Date()
            try context.save()
            return existing
        }

        guard cleanNote != nil else { return nil }

        let review = WeeklyReview(weekStartDate: normalisedWeek, note: cleanNote, plan: plan)
        context.insert(review)
        try context.save()
        return review
    }

    static func deleteWeeklyReview(_ review: WeeklyReview, context: ModelContext) throws {
        context.delete(review)
        try context.save()
    }

    // MARK: - Monthly review

    /// The month's reflection, if one has been written.
    static func monthlyReview(
        for plan: MonthlyPlan,
        context: ModelContext
    ) throws -> MonthlyReview? {
        let planID = plan.id
        var descriptor = FetchDescriptor<MonthlyReview>(
            predicate: #Predicate { $0.plan?.id == planID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Writes the month's reflection, creating it only if an answer was given.
    ///
    /// At most one per month: an existing reflection is updated in place, so it
    /// keeps its id and createdAt and only updatedAt moves.
    @discardableResult
    static func saveMonthlyReview(
        for plan: MonthlyPlan,
        spentMoreThanExpected: String?,
        avoidablePurchase: String?,
        worthwhilePurchase: String?,
        changeNextMonth: String?,
        additionalNotes: String?,
        context: ModelContext
    ) throws -> MonthlyReview? {

        let answers = [
            spentMoreThanExpected, avoidablePurchase, worthwhilePurchase,
            changeNextMonth, additionalNotes
        ].map(normalised)

        let existing = try monthlyReview(for: plan, context: context)
        guard let review = existing ?? (answers.contains { $0 != nil }
                                        ? MonthlyReview(plan: plan) : nil) else {
            // Nothing written and nothing to update: leave no empty record.
            return nil
        }

        if existing == nil { context.insert(review) }

        review.spentMoreThanExpected = answers[0]
        review.avoidablePurchase = answers[1]
        review.worthwhilePurchase = answers[2]
        review.changeNextMonth = answers[3]
        review.additionalNotes = answers[4]
        review.updatedAt = Date()

        try context.save()
        return review
    }

    static func deleteMonthlyReview(_ review: MonthlyReview, context: ModelContext) throws {
        context.delete(review)
        try context.save()
    }

    // MARK: - Text

    private static func normalised(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
