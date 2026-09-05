import SwiftUI
import SwiftData

/// A short check-in: where the month stands, and what to keep in mind next.
///
/// The figures are recomputed from the ledger every time this opens. Nothing
/// financial is stored on the review, so an old check-in can never contradict
/// the records it was written about.
struct WeeklyReviewView: View {

    let plan: MonthlyPlan
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var summary: MonthlySummary { FinanceCalculator.summary(for: plan) }

    private var needingAttention: [BudgetCategory] {
        FinanceCalculator.categoriesNeedingAttention(for: plan)
    }

    var body: some View {
        Form {
            Section("WHERE THE MONTH STANDS") {
                money("Safe to Spend", summary.safeToSpend,
                      emphasised: true, id: "weeklySafeToSpend")
                money("Spent This Month", summary.totalSpent, id: "weeklySpent")
                money("Money Remaining", summary.moneyRemaining, id: "weeklyMoneyRemaining")
            }

            if !needingAttention.isEmpty {
                Section("CATEGORIES NEAR LIMIT") {
                    ForEach(needingAttention) { category in
                        LabeledContent(category.name) {
                            Text("\(FinanceCalculator.spent(in: category).currencyText) / \(category.monthlyBudget.currencyText)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(
                                    FinanceCalculator.isOverBudget(category) ? .red : .secondary
                                )
                        }
                        .accessibilityIdentifier("nearLimit-\(category.name)")
                    }
                }
            }

            Section("WHAT SHOULD I KEEP IN MIND NEXT WEEK?") {
                TextField("Cook at home more. Skip the Friday takeaway.",
                          text: $note, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("weeklyReviewNoteField")
                    .accessibilityLabel("Notes for next week")
            }
        }
        .navigationTitle("Week of \(ReviewView.weekLabel(weekStart))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("saveWeeklyReviewButton")
            }
        }
        .alert("Could not save", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: load)
    }

    private func money(_ label: String, _ amount: Decimal,
                       emphasised: Bool = false, id: String) -> some View {
        LabeledContent(label) {
            Text(amount.currencyText)
                .font(emphasised ? .body.monospacedDigit().weight(.semibold)
                                 : .body.monospacedDigit())
                .foregroundStyle(emphasised && amount < 0 ? .red : .primary)
        }
        .accessibilityIdentifier(id)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        note = (try? ReviewService.weeklyReview(
            for: plan, weekStart: weekStart, context: context
        ))??.note ?? ""
    }

    private func save() {
        do {
            // A blank note on a week never written leaves no record behind.
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: weekStart, note: note, context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
