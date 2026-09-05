import Foundation

/// One thing that happened to the month's money, whichever kind of record it
/// came from.
///
/// Derived in memory only. There is no Activity model in the store, because
/// this is a view of the expenses and Money Added entries that already exist,
/// not a third kind of financial fact.
struct LedgerActivity: Identifiable, Equatable {

    enum Kind: Equatable {
        case expense
        case moneyAdded
    }

    let id: UUID
    let kind: Kind
    let title: String

    /// "Eating Out", "Uncategorized", or "Money Added".
    let subtitle: String

    /// Always the stored, positive amount.
    let amount: Decimal

    let date: Date
    let createdAt: Date

    /// Signed for display only. The stored value never changes.
    var displayAmount: String {
        switch kind {
        case .expense: "-\(amount.currencyText)"
        case .moneyAdded: amount.signedCurrencyText
        }
    }
}

enum ActivityFeed {

    /// The month's expenses and Money Added entries as one list, newest first.
    ///
    /// Ordering is by the financial event date, then `createdAt` as a
    /// tie-breaker so two things dated the same day keep a stable order rather
    /// than shuffling between renders, and finally by id so the order is total
    /// even for records created in the same instant.
    static func activity(for plan: MonthlyPlan, limit: Int? = nil) -> [LedgerActivity] {
        let expenses = plan.expenses.map { expense in
            LedgerActivity(
                id: expense.id,
                kind: .expense,
                title: expense.merchant,
                subtitle: expense.category?.name ?? "Uncategorized",
                amount: expense.amount,
                date: expense.date,
                createdAt: expense.createdAt
            )
        }

        let added = plan.moneyAdded.map { entry in
            LedgerActivity(
                id: entry.id,
                kind: .moneyAdded,
                title: entry.source,
                subtitle: "Money Added",
                amount: entry.amount,
                date: entry.date,
                createdAt: entry.createdAt
            )
        }

        let combined = (expenses + added).sorted { first, second in
            if first.date != second.date { return first.date > second.date }
            if first.createdAt != second.createdAt { return first.createdAt > second.createdAt }
            return first.id.uuidString > second.id.uuidString
        }

        guard let limit else { return combined }
        return Array(combined.prefix(limit))
    }
}
