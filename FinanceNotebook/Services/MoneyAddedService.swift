import Foundation
import SwiftData

enum MoneyAddedError: Error, Equatable {

    case amountNotPositive
    case blankSource

    /// The date falls outside the month the entry belongs to.
    case dateOutsidePlanMonth(monthTitle: String)

    /// The entry is not attached to a month at all.
    case missingPlan

    /// The month has been closed and is read-only.
    case planIsClosed(monthTitle: String)
}

extension MoneyAddedError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .amountNotPositive:
            "Enter an amount greater than zero."
        case .blankSource:
            "Enter where this money came from."
        case .dateOutsidePlanMonth(let monthTitle):
            "Pick a date in \(monthTitle). This entry belongs to that month."
        case .missingPlan:
            "This entry is not attached to a month."
        case .planIsClosed(let monthTitle):
            "\(monthTitle) is closed. Money Added cannot be changed in a closed month."
        }
    }
}

/// All Money Added writes go through here, so the same rules apply wherever an
/// entry is created or changed and views stay free of validation.
///
/// Money Added is not income and not negative spending: it is extra money that
/// became available during the month. It only ever increases the pool the month
/// has to work with.
enum MoneyAddedService {

    // MARK: - Create

    @discardableResult
    static func createEntry(
        amount: Decimal,
        date: Date,
        source: String,
        note: String?,
        plan: MonthlyPlan,
        context: ModelContext
    ) throws -> MoneyAddedEntry {

        try requireOpen(plan)

        let clean = try validate(
            amount: amount, date: date, source: source, note: note, plan: plan
        )

        let entry = MoneyAddedEntry(
            amount: amount,
            date: date,
            source: clean.source,
            note: clean.note,
            plan: plan
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    // MARK: - Update

    /// Edits the entry in place. Deliberately not delete-and-recreate: the
    /// record keeps its identity, its id and its createdAt.
    static func updateEntry(
        _ entry: MoneyAddedEntry,
        amount: Decimal,
        date: Date,
        source: String,
        note: String?,
        context: ModelContext
    ) throws {

        guard let plan = entry.plan else { throw MoneyAddedError.missingPlan }
        try requireOpen(plan)

        let clean = try validate(
            amount: amount, date: date, source: source, note: note, plan: plan
        )

        entry.amount = abs(amount)
        entry.date = date
        entry.source = clean.source
        entry.note = clean.note

        try context.save()
    }

    // MARK: - Delete

    /// Removes the entry only. Expenses and the month itself are untouched;
    /// the month simply has that much less money available.
    static func deleteEntry(_ entry: MoneyAddedEntry, context: ModelContext) throws {
        if let plan = entry.plan { try requireOpen(plan) }
        context.delete(entry)
        try context.save()
    }

    // MARK: - Closure

    /// A closed month is history and does not accept changes.
    private static func requireOpen(_ plan: MonthlyPlan) throws {
        guard !plan.isClosed else {
            throw MoneyAddedError.planIsClosed(monthTitle: plan.displayTitle)
        }
    }

    // MARK: - Validation

    /// Returns the cleaned text values, or throws the first rule broken.
    @discardableResult
    static func validate(
        amount: Decimal,
        date: Date,
        source: String,
        note: String?,
        plan: MonthlyPlan
    ) throws -> (source: String, note: String?) {

        guard amount > 0 else { throw MoneyAddedError.amountNotPositive }

        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { throw MoneyAddedError.blankSource }

        guard plan.contains(date) else {
            throw MoneyAddedError.dateOutsidePlanMonth(monthTitle: plan.displayTitle)
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedSource, (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote)
    }
}
