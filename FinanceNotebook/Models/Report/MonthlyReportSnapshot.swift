import Foundation

/// Everything a report needs, worked out once.
///
/// A plain struct, never a `@Model`. A report is a way of looking at the month,
/// not a new financial fact, so nothing here is persisted -- no stored totals,
/// no export history, no saved PDF paths. It is rebuilt from the ledger each
/// time it is asked for.
///
/// Both the screen and the PDF render from this same value. That is deliberate:
/// if each did its own arithmetic they could drift by a cent, and a report that
/// disagrees with the app is worse than no report.
struct MonthlyReportSnapshot: Equatable {

    let month: Int
    let year: Int
    let monthTitle: String

    /// A closed month is finished; an open one is still moving, and the report
    /// says so rather than implying it is final.
    let isClosed: Bool

    let generatedAt: Date

    /// Straight from FinanceCalculator. The report does no money arithmetic.
    let summary: MonthlySummary

    let categories: [CategoryRow]

    /// Present only when spending exists with no category behind it.
    let uncategorized: UncategorizedRow?

    let moneyAdded: [MoneyAddedRow]
    let expenses: [ExpenseRow]
    let weeklyReviews: [WeeklyReviewRow]
    let reflection: ReflectionRow?

    // MARK: - Rows

    struct CategoryRow: Equatable, Identifiable {
        let id: UUID
        let name: String
        let typeName: String
        let budget: Decimal
        let spent: Decimal

        /// Negative when over budget. Never clamped.
        let remaining: Decimal

        let isOverBudget: Bool

        /// True when there is no budget to measure against.
        let hasNoBudget: Bool
    }

    struct UncategorizedRow: Equatable {
        let spent: Decimal
        let expenseCount: Int
    }

    struct MoneyAddedRow: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let source: String
        let amount: Decimal
        let note: String?
    }

    struct ExpenseRow: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let merchant: String

        /// "Uncategorized" when the category was deleted. Never omitted.
        let categoryName: String

        let amount: Decimal
        let note: String?
    }

    struct WeeklyReviewRow: Equatable, Identifiable {
        let id: UUID
        let weekStartDate: Date
        let note: String?
    }

    /// Only the questions that were actually answered.
    struct ReflectionRow: Equatable {
        let answers: [Answer]

        struct Answer: Equatable, Identifiable {
            let id: String
            let question: String
            let answer: String
        }

        var isEmpty: Bool { answers.isEmpty }
    }
}
