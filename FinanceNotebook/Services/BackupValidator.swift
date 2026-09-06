import Foundation

enum BackupError: Error, Equatable {

    case malformedBackup
    case unsupportedBackupVersion(found: Int, supported: Int)

    case invalidMonth(month: Int)
    case monthKeyMismatch(monthKey: String, expected: String)
    case duplicateMonth(monthKey: String)

    case negativeStartingBalance
    case negativeProtectedAmount
    case negativeBudget

    case invalidDecimal(value: String)
    case invalidAmount(value: String)

    case invalidCategoryType(value: String)

    case duplicateIdentifier(id: UUID)
    case missingPlanReference(id: UUID)
    case missingCategoryReference(id: UUID)
    case crossPlanCategory(expense: UUID)

    case duplicateMonthlyReview(planID: UUID)
    case duplicateWeeklyReview(planID: UUID)

    case restoreFailed
    case restoreVerificationFailed
}

extension BackupError: LocalizedError {

    /// What the user is told. Deliberately plain: raw CoreData or decoding
    /// errors say nothing useful to the person holding the phone.
    var errorDescription: String? {
        switch self {
        case .malformedBackup:
            "This file doesn't appear to be a valid Finance Notebook backup."
        case .unsupportedBackupVersion:
            "This backup was created by a newer version of Finance Notebook and can't be restored by this version."
        case .invalidMonth, .monthKeyMismatch, .duplicateMonth:
            "This backup contains a month that isn't valid, so it can't be restored."
        case .negativeStartingBalance, .negativeProtectedAmount, .negativeBudget,
             .invalidDecimal, .invalidAmount:
            "This backup contains an amount that isn't valid, so it can't be restored."
        case .invalidCategoryType:
            "This backup contains a category type this version doesn't recognise."
        case .duplicateIdentifier:
            "This backup contains duplicated records, so it can't be restored."
        case .missingPlanReference, .missingCategoryReference, .crossPlanCategory:
            "This backup is missing records that other records depend on, so it can't be restored."
        case .duplicateMonthlyReview, .duplicateWeeklyReview:
            "This backup contains conflicting reviews, so it can't be restored."
        case .restoreFailed:
            "The backup couldn't be restored. Your existing data has not been changed."
        case .restoreVerificationFailed:
            "The restored data didn't match the backup, so the restore was stopped."
        }
    }
}

/// Everything that can be checked about a backup, checked before the database
/// is touched at all.
///
/// This is a pure function over decoded values. That is the whole point: a bad
/// file must be rejected while the live store is still untouched, rather than
/// discovered halfway through writing it. SwiftData is not asked to find the
/// problems -- by the time it could, the damage would already be done.
enum BackupValidator {

    /// A backup that has been fully checked. Only a validated backup can be
    /// restored, which is enforced by the type rather than by remembering to
    /// call the validator first.
    struct Validated: Identifiable {
        let backup: FinanceNotebookBackup
        let preview: BackupPreview

        /// So a validated backup can drive `.sheet(item:)`.
        var id: Date { preview.exportedAt }
    }

    static func decode(_ data: Data) throws -> FinanceNotebookBackup {
        do {
            return try BackupCoding.makeDecoder().decode(FinanceNotebookBackup.self, from: data)
        } catch {
            throw BackupError.malformedBackup
        }
    }

    static func validate(data: Data) throws -> Validated {
        try validate(backup: try decode(data))
    }

    static func validate(backup: FinanceNotebookBackup) throws -> Validated {

        // Version first. A newer format may mean anything at all, so nothing
        // else is worth inspecting.
        guard backup.formatVersion <= FinanceNotebookBackup.currentFormatVersion else {
            throw BackupError.unsupportedBackupVersion(
                found: backup.formatVersion,
                supported: FinanceNotebookBackup.currentFormatVersion
            )
        }
        guard backup.formatVersion > 0 else { throw BackupError.malformedBackup }

        var seenIdentifiers: Set<UUID> = []
        func claim(_ id: UUID) throws {
            guard seenIdentifiers.insert(id).inserted else {
                throw BackupError.duplicateIdentifier(id: id)
            }
        }

        // --- Plans ----------------------------------------------------------
        var planIDs: Set<UUID> = []
        var monthKeys: Set<String> = []

        for plan in backup.plans {
            try claim(plan.id)

            guard (1...12).contains(plan.month) else {
                throw BackupError.invalidMonth(month: plan.month)
            }

            // The key is stored, so it can disagree with the month it claims to
            // describe. Restoring that would give the app two different answers
            // to "which month is this".
            let expected = MonthlyPlan.makeMonthKey(month: plan.month, year: plan.year)
            guard plan.monthKey == expected else {
                throw BackupError.monthKeyMismatch(monthKey: plan.monthKey, expected: expected)
            }

            guard monthKeys.insert(plan.monthKey).inserted else {
                throw BackupError.duplicateMonth(monthKey: plan.monthKey)
            }

            let starting = try decimal(plan.startingBalance)
            guard starting >= 0 else { throw BackupError.negativeStartingBalance }

            let protected = try decimal(plan.protectedAmount)
            guard protected >= 0 else { throw BackupError.negativeProtectedAmount }

            planIDs.insert(plan.id)
        }

        // --- Categories -------------------------------------------------------
        var categoryPlan: [UUID: UUID] = [:]

        for category in backup.categories {
            try claim(category.id)
            guard planIDs.contains(category.planID) else {
                throw BackupError.missingPlanReference(id: category.planID)
            }
            guard CategoryType(rawValue: category.type) != nil else {
                // A type this version does not know cannot be guessed at. Picking
                // one arbitrarily would silently rewrite the user's budget.
                throw BackupError.invalidCategoryType(value: category.type)
            }
            let budget = try decimal(category.monthlyBudget)
            guard budget >= 0 else { throw BackupError.negativeBudget }

            categoryPlan[category.id] = category.planID
        }

        // --- Expenses ----------------------------------------------------------
        for expense in backup.expenses {
            try claim(expense.id)
            guard planIDs.contains(expense.planID) else {
                throw BackupError.missingPlanReference(id: expense.planID)
            }

            let amount = try decimal(expense.amount)
            guard amount > 0 else { throw BackupError.invalidAmount(value: expense.amount) }

            if let categoryID = expense.categoryID {
                guard let owner = categoryPlan[categoryID] else {
                    throw BackupError.missingCategoryReference(id: categoryID)
                }
                // An expense in September pointing at an October category is
                // corruption. Restoring it as uncategorized would hide that.
                guard owner == expense.planID else {
                    throw BackupError.crossPlanCategory(expense: expense.id)
                }
            }
        }

        // --- Money added --------------------------------------------------------
        for entry in backup.moneyAdded {
            try claim(entry.id)
            guard planIDs.contains(entry.planID) else {
                throw BackupError.missingPlanReference(id: entry.planID)
            }
            let amount = try decimal(entry.amount)
            guard amount > 0 else { throw BackupError.invalidAmount(value: entry.amount) }
        }

        // --- Reviews -------------------------------------------------------------
        var weeksByPlan: [UUID: Set<Date>] = [:]
        for review in backup.weeklyReviews {
            try claim(review.id)
            guard planIDs.contains(review.planID) else {
                throw BackupError.missingPlanReference(id: review.planID)
            }
            // Compared after normalising, since two dates in one week are one
            // week as far as the app is concerned.
            let week = ReviewService.weekStart(for: review.weekStartDate)
            guard weeksByPlan[review.planID, default: []].insert(week).inserted else {
                throw BackupError.duplicateWeeklyReview(planID: review.planID)
            }
        }

        var plansWithReflection: Set<UUID> = []
        for review in backup.monthlyReviews {
            try claim(review.id)
            guard planIDs.contains(review.planID) else {
                throw BackupError.missingPlanReference(id: review.planID)
            }
            guard plansWithReflection.insert(review.planID).inserted else {
                throw BackupError.duplicateMonthlyReview(planID: review.planID)
            }
        }

        return Validated(backup: backup, preview: makePreview(backup))
    }

    // MARK: - Helpers

    private static func decimal(_ string: String) throws -> Decimal {
        guard let value = BackupCoding.decodeDecimal(string) else {
            throw BackupError.invalidDecimal(value: string)
        }
        return value
    }

    static func makePreview(_ backup: FinanceNotebookBackup) -> BackupPreview {
        let sorted = backup.plans.sorted { $0.monthKey < $1.monthKey }
        return BackupPreview(
            exportedAt: backup.exportedAt,
            formatVersion: backup.formatVersion,
            planCount: backup.plans.count,
            categoryCount: backup.categories.count,
            expenseCount: backup.expenses.count,
            moneyAddedCount: backup.moneyAdded.count,
            weeklyReviewCount: backup.weeklyReviews.count,
            monthlyReviewCount: backup.monthlyReviews.count,
            oldestMonthTitle: sorted.first.map(monthTitle),
            newestMonthTitle: sorted.last.map(monthTitle)
        )
    }

    private static func monthTitle(_ plan: BackupPlan) -> String {
        var components = DateComponents()
        components.month = plan.month
        components.year = plan.year
        guard let date = Calendar.current.date(from: components) else { return plan.monthKey }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
