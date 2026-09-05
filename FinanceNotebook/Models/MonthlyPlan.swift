import Foundation
import SwiftData

/// One calendar month of money. A plan owns everything recorded inside it:
/// its budget categories, its expenses, and any money added during the month.
@Model
final class MonthlyPlan {

    @Attribute(.unique) var id: UUID = UUID()

    /// Canonical "YYYY-MM" key for this plan's calendar month, e.g. "2026-09".
    ///
    /// SwiftData cannot express uniqueness across two attributes, so month and
    /// year are collapsed into one unique key. This is the persistence-layer
    /// backstop behind MonthlyPlanService's duplicate check.
    ///
    /// Derived in `init` and has no setter, so it cannot drift out of step with
    /// `month` and `year`.
    @Attribute(.unique) private(set) var monthKey: String = ""

    private(set) var month: Int = 1
    private(set) var year: Int = 2000

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

    @Relationship(deleteRule: .cascade, inverse: \Expense.plan)
    var expenses: [Expense] = []

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
        self.monthKey = Self.makeMonthKey(month: month, year: year)
        self.startingBalance = startingBalance
        self.protectedAmount = protectedAmount
        self.isClosed = false
        self.createdAt = Date()
    }
}

extension MonthlyPlan {

    /// The canonical key for a calendar month: (9, 2026) -> "2026-09".
    ///
    /// The single place this format is defined. Callers that need to look a
    /// plan up by month must use this rather than building the string
    /// themselves.
    static func makeMonthKey(month: Int, year: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    /// The calendar range this plan covers. Computed, never stored.
    var monthInterval: DateInterval? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        guard
            let start = calendar.date(from: components),
            let dayRange = calendar.range(of: .day, in: .month, for: start),
            let end = calendar.date(byAdding: .day, value: dayRange.count, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Whether a date falls inside this plan's calendar month.
    ///
    /// An expense belongs to a month, so its date has to agree with that month
    /// rather than quietly sitting outside it.
    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: date) == month
            && calendar.component(.year, from: date) == year
    }

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
