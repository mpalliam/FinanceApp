import SwiftUI
import SwiftData

/// The end-of-month look back: what the month cost, and what the user makes of
/// it. The summary is derived; only the answers are kept.
struct MonthlyReflectionView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var spentMoreThanExpected = ""
    @State private var avoidablePurchase = ""
    @State private var worthwhilePurchase = ""
    @State private var changeNextMonth = ""
    @State private var additionalNotes = ""
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var summary: MonthlySummary { FinanceCalculator.summary(for: plan) }

    private var categories: [BudgetCategory] {
        plan.categories.sorted {
            FinanceCalculator.spent(in: $0) > FinanceCalculator.spent(in: $1)
        }
    }

    var body: some View {
        Form {
            summarySection
            if !categories.isEmpty { categorySection }

            // Plain questions, no scoring and no verdict. The numbers are above;
            // what they mean is the user's to decide.
            question("Did I spend more than I expected?",
                     text: $spentMoreThanExpected, id: "spentMoreThanExpectedField")
            question("Was there a purchase I regret or could have avoided?",
                     text: $avoidablePurchase, id: "avoidablePurchaseField")
            question("What purchase felt worthwhile?",
                     text: $worthwhilePurchase, id: "worthwhilePurchaseField")
            question("What should I change next month?",
                     text: $changeNextMonth, id: "changeNextMonthField")
            question("Anything else I want to remember?",
                     text: $additionalNotes, id: "additionalNotesField")
        }
        .navigationTitle("Monthly Reflection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("saveMonthlyReflectionButton")
            }
        }
        .alert("Could not save", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: load)
    }

    private var summarySection: some View {
        Section("MONTH SUMMARY") {
            money("Starting Money", summary.startingBalance, id: "reflectionStartingMoney")
            money("Money Added", summary.moneyAdded, id: "reflectionMoneyAdded")
            money("Total Spent", summary.totalSpent, id: "reflectionTotalSpent")
            money("Money Remaining", summary.moneyRemaining, id: "reflectionMoneyRemaining")
            money("Protected Money", summary.protectedAmount, id: "reflectionProtected")
            money("Safe to Spend", summary.safeToSpend, id: "reflectionSafeToSpend")
        }
    }

    private var categorySection: some View {
        Section("CATEGORIES") {
            ForEach(categories) { category in
                LabeledContent(category.name) {
                    Text("\(FinanceCalculator.spent(in: category).currencyText) / \(category.monthlyBudget.currencyText)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(
                            FinanceCalculator.isOverBudget(category) ? .red : .secondary
                        )
                }
                .accessibilityIdentifier("reflectionCategory-\(category.name)")
            }
        }
    }

    private func money(_ label: String, _ amount: Decimal, id: String) -> some View {
        LabeledContent(label) {
            Text(amount.currencyText).font(.body.monospacedDigit())
        }
        .accessibilityIdentifier(id)
    }

    private func question(_ prompt: String, text: Binding<String>, id: String) -> some View {
        Section {
            TextField("Optional", text: text, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier(id)
                .accessibilityLabel(prompt)
        } header: {
            Text(prompt).textCase(nil)
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        // try? on a throwing function returning an Optional gives a double
        // optional; flatten it rather than binding twice.
        let stored = (try? ReviewService.monthlyReview(for: plan, context: context)) ?? nil
        guard let existing = stored else { return }
        spentMoreThanExpected = existing.spentMoreThanExpected ?? ""
        avoidablePurchase = existing.avoidablePurchase ?? ""
        worthwhilePurchase = existing.worthwhilePurchase ?? ""
        changeNextMonth = existing.changeNextMonth ?? ""
        additionalNotes = existing.additionalNotes ?? ""
    }

    private func save() {
        do {
            // All blank on a month never reflected on leaves no record behind.
            try ReviewService.saveMonthlyReview(
                for: plan,
                spentMoreThanExpected: spentMoreThanExpected,
                avoidablePurchase: avoidablePurchase,
                worthwhilePurchase: worthwhilePurchase,
                changeNextMonth: changeNextMonth,
                additionalNotes: additionalNotes,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
