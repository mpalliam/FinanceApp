import SwiftUI
import SwiftData

/// The Money Added part of the Plan screen: what came in this month, and a way
/// to record more. It lives beside the budgets rather than in its own tab
/// because it is part of planning the month, not a separate activity.
struct MoneyAddedSection: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context

    @State private var isAddingMoney = false
    @State private var entryPendingDeletion: MoneyAddedEntry?
    @State private var errorMessage: String?

    /// Newest first.
    private var entries: [MoneyAddedEntry] {
        plan.moneyAdded.sorted { $0.date > $1.date }
    }

    var body: some View {
        Section("MONEY ADDED") {
            if entries.isEmpty {
                emptyState
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        MoneyAddedDetailView(entry: entry)
                    } label: {
                        MoneyAddedRow(entry: entry)
                    }
                    .accessibilityIdentifier("moneyAdded-\(entry.source)")
                    .swipeActions(edge: .trailing) {
                        if !plan.isClosed {
                            // Asks first: a swipe must not destroy a record.
                            Button(role: .destructive) {
                                entryPendingDeletion = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !plan.isClosed {
                Button("Add Money") { isAddingMoney = true }
                    .accessibilityIdentifier("addMoneyButton")
                // The sheet hangs off the button, not off the Section. A
                // Section is not a real view in the presentation hierarchy, so
                // a .sheet attached to one never presents. (.confirmationDialog
                // on a Section does work, which makes the difference easy to
                // miss.)
                    .sheet(isPresented: $isAddingMoney) {
                        AddMoneyAddedView(plan: plan)
                    }
            }
        }
        .confirmationDialog(
            "Delete Money Added?",
            isPresented: Binding(isPresent: $entryPendingDeletion),
            titleVisibility: .visible,
            presenting: entryPendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
                .accessibilityIdentifier("confirmDeleteMoneyFromListButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("cancelDeleteMoneyFromListButton")
        } message: { _ in
            Text("Removing this entry will reduce the money available for this month.")
        }
        .alert("Could not delete", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Money Added")
                .font(.headline)
            Text("If you receive a refund, reimbursement, family money, or other additional funds, record it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("moneyAddedEmptyState")
    }

    private func delete(_ entry: MoneyAddedEntry) {
        do {
            try MoneyAddedService.deleteEntry(entry, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MoneyAddedRow: View {

    let entry: MoneyAddedEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source)
                    .font(.body)
                Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(entry.amount.signedCurrencyText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.green)
        }
        .accessibilityElement(children: .combine)
    }
}
