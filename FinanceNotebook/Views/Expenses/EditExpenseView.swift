import SwiftUI
import SwiftData

struct EditExpenseView: View {

    let expense: Expense

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fields = ExpenseFormFields()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let plan = expense.plan {
                    ExpenseFormView(plan: plan, fields: $fields)
                } else {
                    ContentUnavailableView(
                        "No Month",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("This expense is not attached to a month.")
                    )
                }
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Expense") { save() }
                        .accessibilityIdentifier("saveExpenseButton")
                }
            }
            .alert("Cannot Save", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear(perform: loadExistingValues)
    }

    private func loadExistingValues() {
        // Plain decimal text, not currency-formatted, so it round-trips through
        // the same parser the user's own typing goes through.
        fields.amountText = "\(expense.amount)"
        fields.merchant = expense.merchant
        fields.note = expense.note ?? ""
        fields.date = expense.date
        fields.category = expense.category
    }

    private func save() {
        guard let amount = fields.amount else {
            errorMessage = ExpenseError.amountNotPositive.localizedDescription
            return
        }
        do {
            // Updates in place: same object, same id.
            try ExpenseService.updateExpense(
                expense,
                amount: amount,
                date: fields.date,
                merchant: fields.merchant,
                note: fields.note,
                category: fields.category,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
