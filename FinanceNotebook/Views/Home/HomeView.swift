import SwiftUI
import SwiftData

/// The month at a glance. Every figure comes from FinanceCalculator; this
/// screen does no arithmetic of its own.
struct HomeView: View {

    let plan: MonthlyPlan

    @State private var isAddingExpense = false
    @State private var isAddingMoney = false

    private var summary: MonthlySummary { FinanceCalculator.summary(for: plan) }

    private var recentActivity: [LedgerActivity] {
        ActivityFeed.activity(for: plan, limit: 5)
    }

    /// The few budgets worth glancing at: the ones with the most spent against
    /// them. Plan remains the full picture.
    private var topCategories: [BudgetCategory] {
        plan.categories
            .sorted { FinanceCalculator.spent(in: $0) > FinanceCalculator.spent(in: $1) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                safeToSpendSection
                if plan.isClosed { closedNotice }
                supportingMetricsSection
                if !plan.isClosed { quickActionsSection }
                activitySection
                if !topCategories.isEmpty { budgetsSection }
            }
            .navigationTitle("Finance Notebook")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MonthSelectorButton(plan: plan)
                }
            }
            .sheet(isPresented: $isAddingExpense) {
                AddExpenseView(plan: plan)
            }
            .sheet(isPresented: $isAddingMoney) {
                AddMoneyAddedView(plan: plan)
            }
        }
    }

    // MARK: - Safe to Spend

    private var safeToSpendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("SAFE TO SPEND")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary.safeToSpend.currencyText)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(summary.isProtectedMoneyAtRisk ? .red : .primary)
                    .accessibilityIdentifier("homeSafeToSpend")
                    .accessibilityLabel("Safe to Spend \(summary.safeToSpend.currencyText)")
                if summary.isProtectedMoneyAtRisk {
                    Text("You have started spending money you meant to protect.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text(plan.displayTitle)
        }
    }

    private var closedNotice: some View {
        Section {
            Label("This month is closed. It is read-only.", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("closedMonthNotice")
        }
    }

    // MARK: - Supporting metrics

    private var supportingMetricsSection: some View {
        Section {
            metric("Starting Money", summary.startingBalance.currencyText,
                   id: "homeStartingMoney")
            metric("Money Added",
                   plan.moneyAdded.isEmpty ? summary.moneyAdded.currencyText
                                           : summary.moneyAdded.signedCurrencyText,
                   id: "homeMoneyAdded")
            metric("Spent This Month", summary.totalSpent.currencyText, id: "homeSpent")
            metric("Money Remaining", summary.moneyRemaining.currencyText,
                   id: "homeMoneyRemaining")
            metric("Protected", summary.protectedAmount.currencyText, id: "homeProtected")
        }
    }

    private func metric(_ label: String, _ value: String, id: String) -> some View {
        LabeledContent(label) {
            Text(value).font(.body.monospacedDigit())
        }
        .accessibilityIdentifier(id)
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        Section {
            Button {
                isAddingExpense = true
            } label: {
                Label("Add Expense", systemImage: "minus.circle")
            }
            .accessibilityIdentifier("homeAddExpenseButton")

            Button {
                isAddingMoney = true
            } label: {
                Label("Add Money", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("homeAddMoneyButton")
        }
    }

    // MARK: - Recent activity

    @ViewBuilder
    private var activitySection: some View {
        Section("RECENT ACTIVITY") {
            if recentActivity.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Activity Yet").font(.headline)
                    Text("Expenses and money you add this month will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("homeActivityEmptyState")
            } else {
                ForEach(recentActivity) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Text(item.displayAmount)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(item.kind == .moneyAdded ? .green : .primary)
                    }
                    // Combine first, then identify: applying .combine afterwards
                    // builds a fresh element and the identifier is lost with it.
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("activity-\(item.title)")
                }
            }
        }
    }

    // MARK: - Budget snapshot

    private var budgetsSection: some View {
        Section("BUDGETS") {
            ForEach(topCategories) { category in
                LabeledContent(category.name) {
                    Text("\(FinanceCalculator.spent(in: category).currencyText) / \(category.monthlyBudget.currencyText)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(
                            FinanceCalculator.isOverBudget(category) ? .red : .secondary
                        )
                }
                .accessibilityIdentifier("homeBudget-\(category.name)")
            }
        }
    }
}
