import SwiftUI
import SwiftData

/// What the backup contains, and then the destructive choice.
///
/// The preview shows counts and a date range, never the records themselves. A
/// confirmation screen is not the place to display somebody's transactions.
struct RestoreBackupView: View {

    let validated: BackupValidator.Validated
    var onRestored: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MonthSelection.self) private var selection

    @State private var isConfirmingReplace = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var didRestore = false

    private var preview: BackupPreview { validated.preview }

    private var hasExistingData: Bool {
        BackupService.hasExistingData(in: context)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("CREATED") {
                    Text(preview.exportedAt.formatted(date: .long, time: .shortened))
                        .accessibilityIdentifier("backupExportedAt")
                }

                Section("CONTAINS") {
                    count("Months", preview.planCount, id: "backupMonthCount")
                    count("Categories", preview.categoryCount, id: "backupCategoryCount")
                    count("Expenses", preview.expenseCount, id: "backupExpenseCount")
                    count("Money Added", preview.moneyAddedCount, id: "backupMoneyAddedCount")
                    count("Weekly Reviews", preview.weeklyReviewCount, id: "backupWeeklyCount")
                    count("Monthly Reflections", preview.monthlyReviewCount,
                          id: "backupMonthlyCount")
                }

                if let oldest = preview.oldestMonthTitle,
                   let newest = preview.newestMonthTitle {
                    Section("RANGE") {
                        LabeledContent("Oldest Month", value: oldest)
                        LabeledContent("Newest Month", value: newest)
                    }
                }

                actionSection
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("restoreBackupView")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Replace Existing Data?",
                isPresented: $isConfirmingReplace,
                titleVisibility: .visible
            ) {
                Button("Replace Existing Data", role: .destructive) { restore() }
                    .accessibilityIdentifier("confirmReplaceButton")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelReplaceButton")
            } message: {
                Text("This will remove the Finance Notebook data currently on this device and replace it with the selected backup.\n\nThis cannot be undone unless you have another backup.")
            }
            .alert("Couldn't Restore Backup",
                   isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Backup Restored", isPresented: $didRestore) {
                Button("OK") {
                    dismiss()
                    onRestored()
                }
            } message: {
                Text("Your notebook now matches the backup.")
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if hasExistingData {
                Button(role: .destructive) {
                    isConfirmingReplace = true
                } label: {
                    Text("Replace Existing Data")
                }
                .accessibilityIdentifier("replaceExistingDataButton")
                .disabled(isRestoring)
            } else {
                Button("Restore Backup") { restore() }
                    .accessibilityIdentifier("restoreIntoEmptyButton")
                    .disabled(isRestoring)
            }
        } footer: {
            if hasExistingData {
                Text("This device already has Finance Notebook data. Restoring will remove it.")
            } else if preview.isEmpty {
                Text("This backup contains no months.")
            }
        }
    }

    private func count(_ label: String, _ value: Int, id: String) -> some View {
        LabeledContent(label, value: "\(value)")
            .accessibilityIdentifier(id)
    }

    private func restore() {
        isRestoring = true
        do {
            try BackupRestorer.restore(validated, into: context)

            // The month that was selected may no longer exist. Clearing the key
            // lets MonthSelection fall back rather than leaving the app pointed
            // at a deleted object.
            let restoredKeys = Set(validated.backup.plans.map(\.monthKey))
            if let current = selection.monthKey, !restoredKeys.contains(current) {
                selection.monthKey = nil
            }

            didRestore = true
        } catch let error as BackupError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = BackupError.restoreFailed.localizedDescription
        }
        isRestoring = false
    }
}
