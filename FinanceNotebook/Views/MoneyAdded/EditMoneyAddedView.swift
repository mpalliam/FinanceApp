import SwiftUI
import SwiftData

struct EditMoneyAddedView: View {

    let entry: MoneyAddedEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fields = MoneyAddedFormFields()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let plan = entry.plan {
                    MoneyAddedFormView(plan: plan, fields: $fields)
                } else {
                    ContentUnavailableView(
                        "No Month",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("This entry is not attached to a month.")
                    )
                }
            }
            .navigationTitle("Edit Money Added")
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
        .onAppear(perform: loadExistingValues)
    }

    private func loadExistingValues() {
        // Plain decimal text, so it round-trips through the same parser the
        // user's own typing goes through.
        fields.amountText = "\(entry.amount)"
        fields.source = entry.source
        fields.note = entry.note ?? ""
        fields.date = entry.date
    }

    private func save() {
        guard let amount = fields.amount else {
            errorMessage = MoneyAddedError.amountNotPositive.localizedDescription
            return
        }
        do {
            // Updates in place: same object, same id.
            try MoneyAddedService.updateEntry(
                entry,
                amount: amount,
                date: fields.date,
                source: fields.source,
                note: fields.note,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
