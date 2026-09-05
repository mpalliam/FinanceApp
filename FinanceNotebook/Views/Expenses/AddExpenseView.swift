import SwiftUI
import SwiftData

struct AddExpenseView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fields = ExpenseFormFields()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ExpenseFormView(plan: plan, fields: $fields)
                .navigationTitle("Add Expense")
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
        .onAppear {
            // Default to today, but only if today is inside this month.
            if !plan.contains(fields.date), let start = plan.monthInterval?.start {
                fields.date = start
            }
            if fields.category == nil, plan.categories.count == 1 {
                fields.category = plan.categories.first
            }
        }
    }

    private func save() {
        guard let amount = fields.amount else {
            errorMessage = ExpenseError.amountNotPositive.localizedDescription
            return
        }
        do {
            try ExpenseService.createExpense(
                amount: amount,
                date: fields.date,
                merchant: fields.merchant,
                note: fields.note,
                category: fields.category,
                plan: plan,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
