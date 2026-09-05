import SwiftUI
import SwiftData

/// Edits the month's starting and protected money.
///
/// Only those two. The month itself is not editable here: month, year and
/// monthKey stay locked down on the model so they cannot drift apart.
struct EditMonthlyPlanView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var startingText = ""
    @State private var protectedText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Starting Money") {
                    TextField("0.00", text: $startingText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("startingMoneyField")
                        .accessibilityLabel("Starting Money")
                }

                Section("Protected Money") {
                    TextField("0.00", text: $protectedText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("protectedMoneyField")
                        .accessibilityLabel("Protected Money")
                }

                Section {
                    Text("Protected money is money you intend not to spend. It is not an expense, so it still counts as money you have.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(plan.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("savePlanMoneyButton")
                }
            }
            .alert("Cannot Save", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            startingText = "\(plan.startingBalance)"
            protectedText = "\(plan.protectedAmount)"
        }
    }

    private func save() {
        guard
            let starting = Decimal(string: startingText.trimmingCharacters(in: .whitespaces),
                                   locale: .current),
            let protected = Decimal(string: protectedText.trimmingCharacters(in: .whitespaces),
                                    locale: .current)
        else {
            errorMessage = "Enter both amounts as numbers."
            return
        }

        do {
            try MonthlyPlanService.updateMoney(
                plan,
                startingBalance: starting,
                protectedAmount: protected,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
