import SwiftUI
import SwiftData

struct AddMoneyAddedView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fields = MoneyAddedFormFields()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            MoneyAddedFormView(plan: plan, fields: $fields)
                .navigationTitle("Add Money")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .accessibilityIdentifier("saveMoneyButton")
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
        }
    }

    private func save() {
        guard let amount = fields.amount else {
            errorMessage = MoneyAddedError.amountNotPositive.localizedDescription
            return
        }
        do {
            try MoneyAddedService.createEntry(
                amount: amount,
                date: fields.date,
                source: fields.source,
                note: fields.note,
                plan: plan,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
