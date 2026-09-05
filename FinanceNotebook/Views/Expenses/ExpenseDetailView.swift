import SwiftUI
import SwiftData

struct ExpenseDetailView: View {

    let expense: Expense

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(expense.merchant)
                        .font(.title2.weight(.semibold))
                    Text(expense.amount.currencyText)
                        .font(.largeTitle.monospacedDigit())
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Category", value: expense.category?.name ?? "Uncategorized")
                LabeledContent("Date", value: expense.date.formatted(date: .long, time: .omitted))
                if let note = expense.note, !note.isEmpty {
                    LabeledContent("Note", value: note)
                }
            }

            Section {
                Button("Delete Expense", role: .destructive) {
                    isConfirmingDelete = true
                }
                .accessibilityIdentifier("deleteExpenseButton")
            }
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("editExpenseButton")
            }
        }
        .sheet(isPresented: $isEditing) {
            EditExpenseView(expense: expense)
        }
        .confirmationDialog(
            "Delete Expense?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
                .accessibilityIdentifier("confirmDeleteButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("cancelDeleteButton")
        } message: {
            Text("This will permanently remove this expense.")
        }
        .alert("Could not delete", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete() {
        do {
            try ExpenseService.deleteExpense(expense, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
