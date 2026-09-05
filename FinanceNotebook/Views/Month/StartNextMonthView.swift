import SwiftUI
import SwiftData

/// The rollover screen: what the next month will start with, and why.
struct StartNextMonthView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MonthSelection.self) private var selection

    @State private var startingText = ""
    @State private var protectedText = ""
    @State private var copyCategories = true
    @State private var errorMessage: String?

    private var defaults: RolloverDefaults {
        MonthlyPlanService.rolloverDefaults(from: plan)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Starting Money") {
                    TextField("0.00", text: $startingText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("startingMoneyField")
                        .accessibilityLabel("Starting Money")

                    if defaults.startingBalanceWasClamped {
                        // Say what happened rather than silently showing zero.
                        Text("\(plan.displayTitle) ended at \(defaults.previousMoneyRemaining.currencyText). Starting Money cannot be negative, so \(defaults.monthTitle) starts at \(Decimal.zero.currencyText) by default. You can adjust this before creating the month.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("negativeRolloverNotice")
                    } else {
                        Text("Carried over from \(plan.displayTitle).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Protected Money") {
                    TextField("0.00", text: $protectedText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("protectedMoneyField")
                        .accessibilityLabel("Protected Money")
                }

                Section {
                    Toggle("Copy Categories & Budgets", isOn: $copyCategories)
                        .accessibilityIdentifier("copyCategoriesToggle")

                    if copyCategories {
                        Text(defaults.categoryCount == 1
                             ? "1 category will be copied."
                             : "\(defaults.categoryCount) categories will be copied.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Expenses and Money Added are never carried over. The new month starts empty.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Start \(defaults.monthTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .accessibilityIdentifier("createNextMonthButton")
                }
            }
            .alert("Cannot Create", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            startingText = "\(defaults.startingBalance)"
            protectedText = "\(defaults.protectedAmount)"
        }
    }

    private func create() {
        let starting = Decimal(string: startingText.trimmingCharacters(in: .whitespaces),
                               locale: .current) ?? .zero
        let protected = Decimal(string: protectedText.trimmingCharacters(in: .whitespaces),
                                locale: .current) ?? .zero

        do {
            let newPlan = try MonthlyPlanService.createNextPlan(
                from: plan,
                startingBalance: starting,
                protectedAmount: protected,
                copyCategories: copyCategories,
                context: context
            )
            selection.monthKey = newPlan.monthKey
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
