import Foundation

/// User-facing wording that more than one screen needs to agree on.
///
/// This exists because the same sentences were being written out separately in
/// each place that needed them -- the budget status line lived in three files,
/// and a closed month was described two different ways depending on where you
/// happened to be looking. Wording that says the same thing should be the same
/// string, or it drifts.
///
/// Deliberately not a localisation layer or a design system. It is a handful of
/// shared sentences.
enum FinanceCopy {

    // MARK: - Closed months

    /// The one sentence used wherever a month is read-only.
    static let closedMonthNotice = "This month is closed and can no longer be edited."

    /// The short badge form, for titles and list rows.
    static let closedBadge = "Closed"

    /// Said before closing, so the consequence is clear beforehand rather than
    /// discovered afterwards. Reopening is not offered, so it is not mentioned.
    static let closeMonthWarning = """
        You will no longer be able to edit expenses, money added, budgets, or \
        monthly money for this month.

        Reviews and reports will still be available.
        """

    // MARK: - Categories

    /// How a category is doing against its budget.
    ///
    /// Over budget reports the overspend as a positive number with the word
    /// "over" rather than a negative remaining, because "-$15.00 remaining" is
    /// a sentence nobody says.
    static func budgetStatus(spent: Decimal, budget: Decimal) -> String {
        let remaining = budget - spent
        if spent > budget {
            return "\(abs(remaining).currencyText) over budget"
        }
        if budget == 0 {
            return "No budget set"
        }
        return "\(remaining.currencyText) remaining"
    }

    /// Said before deleting a category that has spending against it. The point
    /// is that nothing is lost and the situation is recoverable.
    static func categoryDeletionWarning(expenseCount count: Int) -> String {
        guard count > 0 else { return "This category has no expenses." }
        let noun = count == 1 ? "expense is" : "expenses are"
        let subject = count == 1 ? "It" : "They"
        return """
            \(count) \(noun) assigned to this category.

            \(subject) will NOT be deleted. \(subject) will become Uncategorized, \
            and can be reassigned to another category later.
            """
    }
}

// MARK: - Release wording

extension FinanceCopy {

    /// Deliberately narrow. It claims local storage and no network, which the
    /// app does, and stops there: backups are plaintext and the user can send
    /// them anywhere, so no broader promise would be true.
    static let privacySummary = """
        Your financial data is stored locally on this device. Finance Notebook \
        has no account, does not connect to your bank, and does not send your \
        financial history anywhere.
        """

    static let exportBeforeDeleting = """
        Because your notebook is stored only on this device, export a backup \
        before deleting Finance Notebook or moving to a new iPhone.
        """

    static let couldNotCreateBackup = "Couldn't Create Backup"
    static let couldNotReadBackup = "Couldn't Read Backup"
}
