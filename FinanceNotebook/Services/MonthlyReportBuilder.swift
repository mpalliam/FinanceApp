import Foundation
import SwiftData

/// Turns a month into a report snapshot.
///
/// Read-only, always. Building a report fetches and sorts; it never inserts,
/// updates, deletes or saves. Looking back at a month must not change it, and
/// that has to hold for closed months too.
///
/// All money arithmetic is delegated to FinanceCalculator. Nothing here
/// recomputes a total, so the report cannot drift from the rest of the app.
enum MonthlyReportBuilder {

    static func makeReport(
        for plan: MonthlyPlan,
        context: ModelContext,
        generatedAt: Date = Date()
    ) -> MonthlyReportSnapshot {

        MonthlyReportSnapshot(
            month: plan.month,
            year: plan.year,
            monthTitle: plan.displayTitle,
            isClosed: plan.isClosed,
            generatedAt: generatedAt,
            summary: FinanceCalculator.summary(for: plan),
            categories: categoryRows(for: plan),
            uncategorized: uncategorizedRow(for: plan),
            moneyAdded: moneyAddedRows(for: plan),
            expenses: expenseRows(for: plan),
            weeklyReviews: weeklyReviewRows(for: plan, context: context),
            reflection: reflectionRow(for: plan, context: context)
        )
    }

    // MARK: - Categories

    /// Alphabetical, so a report of the same month always reads the same way.
    private static func categoryRows(for plan: MonthlyPlan) -> [MonthlyReportSnapshot.CategoryRow] {
        plan.categories
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { category in
                MonthlyReportSnapshot.CategoryRow(
                    id: category.id,
                    name: category.name,
                    typeName: category.type.displayName,
                    budget: category.monthlyBudget,
                    spent: FinanceCalculator.spent(in: category),
                    remaining: FinanceCalculator.remaining(in: category),
                    isOverBudget: FinanceCalculator.isOverBudget(category),
                    hasNoBudget: category.monthlyBudget == 0
                )
            }
    }

    /// Money spent with no category behind it, which happens when a category is
    /// deleted. It still counts toward the month, so a report that left it out
    /// would not add up.
    private static func uncategorizedRow(
        for plan: MonthlyPlan
    ) -> MonthlyReportSnapshot.UncategorizedRow? {
        let orphans = FinanceCalculator.uncategorizedExpenses(for: plan)
        guard !orphans.isEmpty else { return nil }
        return MonthlyReportSnapshot.UncategorizedRow(
            spent: FinanceCalculator.uncategorizedSpent(for: plan),
            expenseCount: orphans.count
        )
    }

    // MARK: - Ledger

    /// Oldest first. A report reads forward through the month like a ledger,
    /// which is the opposite of the app's lists, where the newest thing matters
    /// most.
    ///
    /// `createdAt` then `id` break ties, so two things dated the same day always
    /// come out in the same order and the same month never produces two
    /// different documents.
    private static func moneyAddedRows(
        for plan: MonthlyPlan
    ) -> [MonthlyReportSnapshot.MoneyAddedRow] {
        plan.moneyAdded
            .sorted(by: chronological(\.date, \.createdAt, \.id))
            .map { entry in
                MonthlyReportSnapshot.MoneyAddedRow(
                    id: entry.id,
                    date: entry.date,
                    source: entry.source,
                    amount: entry.amount,
                    note: entry.note
                )
            }
    }

    private static func expenseRows(
        for plan: MonthlyPlan
    ) -> [MonthlyReportSnapshot.ExpenseRow] {
        plan.expenses
            .sorted(by: chronological(\.date, \.createdAt, \.id))
            .map { expense in
                MonthlyReportSnapshot.ExpenseRow(
                    id: expense.id,
                    date: expense.date,
                    merchant: expense.merchant,
                    categoryName: expense.category?.name ?? "Uncategorized",
                    amount: expense.amount,
                    note: expense.note
                )
            }
    }

    // MARK: - Reviews

    /// Oldest first, so the check-ins read as the month progressed.
    private static func weeklyReviewRows(
        for plan: MonthlyPlan,
        context: ModelContext
    ) -> [MonthlyReportSnapshot.WeeklyReviewRow] {
        let reviews = (try? ReviewService.weeklyReviews(for: plan, context: context)) ?? []
        return reviews
            .sorted(by: chronological(\.weekStartDate, \.createdAt, \.id))
            .map { review in
                MonthlyReportSnapshot.WeeklyReviewRow(
                    id: review.id,
                    weekStartDate: review.weekStartDate,
                    note: review.note
                )
            }
    }

    /// Only the questions that were answered. Opening a report never creates a
    /// reflection.
    private static func reflectionRow(
        for plan: MonthlyPlan,
        context: ModelContext
    ) -> MonthlyReportSnapshot.ReflectionRow? {
        let stored = (try? ReviewService.monthlyReview(for: plan, context: context)) ?? nil
        guard let review = stored else { return nil }

        let prompts: [(String, String, String?)] = [
            ("spentMoreThanExpected", "Did I spend more than I expected?",
             review.spentMoreThanExpected),
            ("avoidablePurchase", "Was there a purchase I regret or could have avoided?",
             review.avoidablePurchase),
            ("worthwhilePurchase", "What purchase felt worthwhile?",
             review.worthwhilePurchase),
            ("changeNextMonth", "What should I change next month?",
             review.changeNextMonth),
            ("additionalNotes", "Anything else I want to remember?",
             review.additionalNotes)
        ]

        let answers = prompts.compactMap { id, question, answer -> MonthlyReportSnapshot.ReflectionRow.Answer? in
            guard let answer, !answer.isEmpty else { return nil }
            return .init(id: id, question: question, answer: answer)
        }

        return answers.isEmpty ? nil : .init(answers: answers)
    }

    // MARK: - Ordering

    /// Oldest first, with two tie-breakers so the order is total and the same
    /// month always produces the same document.
    private static func chronological<T>(
        _ date: KeyPath<T, Date>,
        _ created: KeyPath<T, Date>,
        _ id: KeyPath<T, UUID>
    ) -> (T, T) -> Bool {
        { first, second in
            if first[keyPath: date] != second[keyPath: date] {
                return first[keyPath: date] < second[keyPath: date]
            }
            if first[keyPath: created] != second[keyPath: created] {
                return first[keyPath: created] < second[keyPath: created]
            }
            return first[keyPath: id].uuidString < second[keyPath: id].uuidString
        }
    }
}
