import Foundation
import SwiftData

/// Builds and writes backups.
///
/// Read-only, always. Making a copy of the notebook must not alter it -- not a
/// timestamp, not a closed flag, nothing.
enum BackupService {

    // MARK: - Building

    /// Reads the whole notebook into a backup value.
    ///
    /// Arrays are ordered deterministically so two exports of an unchanged
    /// notebook produce the same file, which makes a backup diffable and makes
    /// round-trip tests mean something.
    static func makeBackup(
        from context: ModelContext,
        exportedAt: Date = Date()
    ) throws -> FinanceNotebookBackup {

        let plans = try context.fetch(FetchDescriptor<MonthlyPlan>())
        let categories = try context.fetch(FetchDescriptor<BudgetCategory>())
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let moneyAdded = try context.fetch(FetchDescriptor<MoneyAddedEntry>())
        let weeklyReviews = try context.fetch(FetchDescriptor<WeeklyReview>())
        let monthlyReviews = try context.fetch(FetchDescriptor<MonthlyReview>())

        return FinanceNotebookBackup(
            formatVersion: FinanceNotebookBackup.currentFormatVersion,
            exportedAt: exportedAt,
            sourceSchemaVersion: FinanceNotebookBackup.currentSchemaVersion,

            plans: plans
                .sorted { ($0.year, $0.month, $0.id.uuidString)
                          < ($1.year, $1.month, $1.id.uuidString) }
                .map { plan in
                    BackupPlan(
                        id: plan.id,
                        month: plan.month,
                        year: plan.year,
                        monthKey: plan.monthKey,
                        startingBalance: BackupCoding.encode(plan.startingBalance),
                        protectedAmount: BackupCoding.encode(plan.protectedAmount),
                        isClosed: plan.isClosed,
                        createdAt: plan.createdAt
                    )
                },

            categories: categories
                .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
                .compactMap { category in
                    guard let planID = category.plan?.id else { return nil }
                    return BackupCategory(
                        id: category.id,
                        planID: planID,
                        name: category.name,
                        monthlyBudget: BackupCoding.encode(category.monthlyBudget),
                        type: category.type.rawValue
                    )
                },

            expenses: expenses
                .sorted { ($0.date, $0.createdAt, $0.id.uuidString)
                          < ($1.date, $1.createdAt, $1.id.uuidString) }
                .compactMap { expense in
                    guard let planID = expense.plan?.id else { return nil }
                    return BackupExpense(
                        id: expense.id,
                        planID: planID,
                        categoryID: expense.category?.id,
                        amount: BackupCoding.encode(expense.amount),
                        date: expense.date,
                        merchant: expense.merchant,
                        note: expense.note,
                        createdAt: expense.createdAt
                    )
                },

            moneyAdded: moneyAdded
                .sorted { ($0.date, $0.createdAt, $0.id.uuidString)
                          < ($1.date, $1.createdAt, $1.id.uuidString) }
                .compactMap { entry in
                    guard let planID = entry.plan?.id else { return nil }
                    return BackupMoneyAddedEntry(
                        id: entry.id,
                        planID: planID,
                        amount: BackupCoding.encode(entry.amount),
                        date: entry.date,
                        source: entry.source,
                        note: entry.note,
                        createdAt: entry.createdAt
                    )
                },

            weeklyReviews: weeklyReviews
                .sorted { ($0.weekStartDate, $0.id.uuidString)
                          < ($1.weekStartDate, $1.id.uuidString) }
                .compactMap { review in
                    guard let planID = review.plan?.id else { return nil }
                    return BackupWeeklyReview(
                        id: review.id,
                        planID: planID,
                        weekStartDate: review.weekStartDate,
                        note: review.note,
                        createdAt: review.createdAt,
                        updatedAt: review.updatedAt
                    )
                },

            monthlyReviews: monthlyReviews
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .compactMap { review in
                    guard let planID = review.plan?.id else { return nil }
                    return BackupMonthlyReview(
                        id: review.id,
                        planID: planID,
                        spentMoreThanExpected: review.spentMoreThanExpected,
                        avoidablePurchase: review.avoidablePurchase,
                        worthwhilePurchase: review.worthwhilePurchase,
                        changeNextMonth: review.changeNextMonth,
                        additionalNotes: review.additionalNotes,
                        createdAt: review.createdAt,
                        updatedAt: review.updatedAt
                    )
                }
        )
    }

    // MARK: - Encoding

    static func encode(_ backup: FinanceNotebookBackup) throws -> Data {
        try BackupCoding.makeEncoder().encode(backup)
    }

    // MARK: - Files

    /// e.g. "Finance-Notebook-Backup-2026-09-05-1430.financebackup"
    ///
    /// The time is included so two backups made on one day do not overwrite
    /// each other wherever the user puts them.
    static func fileName(exportedAt: Date = Date()) -> String {
        var formatter = Date.FormatStyle(date: .numeric, time: .omitted)
        formatter.timeZone = .current
        let stamp = exportedAt.formatted(
            .verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
                      timeZone: .current, calendar: .current)
        )
        return "Finance-Notebook-Backup-\(stamp).financebackup"
    }

    /// Writes the backup where the share sheet can reach it.
    ///
    /// The temporary directory, not app storage: a backup is a document the
    /// user is sending somewhere, not data the app keeps.
    @discardableResult
    static func writeBackup(
        from context: ModelContext,
        exportedAt: Date = Date(),
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let backup = try makeBackup(from: context, exportedAt: exportedAt)
        let data = try encode(backup)
        let url = directory.appending(path: fileName(exportedAt: exportedAt))
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Current state

    /// Whether the notebook currently holds anything, so restore can tell the
    /// difference between filling an empty app and overwriting someone's
    /// records.
    static func hasExistingData(in context: ModelContext) -> Bool {
        let counts = [
            (try? context.fetchCount(FetchDescriptor<MonthlyPlan>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<MoneyAddedEntry>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<BudgetCategory>())) ?? 0
        ]
        return counts.contains { $0 > 0 }
    }
}
