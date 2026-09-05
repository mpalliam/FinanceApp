import SwiftUI
import SwiftData

struct MoneyAddedDetailView: View {

    let entry: MoneyAddedEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    /// A closed month is history: it can be read, not rewritten.
    private var isEditable: Bool { !(entry.plan?.isClosed ?? false) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.source)
                        .font(.title2.weight(.semibold))
                    Text(entry.amount.signedCurrencyText)
                        .font(.largeTitle.monospacedDigit())
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Date", value: entry.date.formatted(date: .long, time: .omitted))
                if let note = entry.note, !note.isEmpty {
                    LabeledContent("Note", value: note)
                }
            }

            if isEditable {
                Section {
                    Button("Delete Money Added", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .accessibilityIdentifier("deleteMoneyButton")
                }
            }
        }
        .navigationTitle("Money Added")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                        .accessibilityIdentifier("editMoneyButton")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditMoneyAddedView(entry: entry)
        }
        .confirmationDialog(
            "Delete Money Added?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
                .accessibilityIdentifier("confirmDeleteMoneyButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("cancelDeleteMoneyButton")
        } message: {
            Text("Removing this entry will reduce the money available for this month.")
        }
        .alert("Could not delete", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete() {
        do {
            try MoneyAddedService.deleteEntry(entry, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
