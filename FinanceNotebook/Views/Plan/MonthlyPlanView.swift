import SwiftUI
import SwiftData

/// The month's money and its category budgets.
///
/// Every figure here comes from FinanceCalculator reading the stored records.
/// Nothing is cached, which is why the numbers move as soon as an expense does.
struct MonthlyPlanView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context

    @State private var isEditingMoney = false
    @State private var isAddingCategory = false
    @State private var categoryBeingEdited: BudgetCategory?
    @State private var categoryPendingDeletion: BudgetCategory?
    @State private var errorMessage: String?
    @State private var isStartingNextMonth = false
    @State private var isConfirmingClose = false
    @State private var isShowingUncategorized = false

    private var summary: MonthlySummary { FinanceCalculator.summary(for: plan) }

    private var categories: [BudgetCategory] {
        plan.categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                budgetsSection
                uncategorizedSection
                MoneyAddedSection(plan: plan)
                monthActionsSection
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MonthSelectorButton(plan: plan)
                }
                if !plan.isClosed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingCategory = true
                        } label: {
                            Label("Add Category", systemImage: "plus")
                        }
                        .accessibilityIdentifier("addCategoryButton")
                        .accessibilityLabel("Add Category")
                    }
                }
            }
            .sheet(isPresented: $isStartingNextMonth) {
                StartNextMonthView(plan: plan)
            }
            .sheet(isPresented: $isShowingUncategorized) {
                UncategorizedExpensesView(plan: plan)
            }
            .confirmationDialog(
                "Close \(plan.displayTitle)?",
                isPresented: $isConfirmingClose,
                titleVisibility: .visible
            ) {
                Button("Close Month") { closeMonth() }
                    .accessibilityIdentifier("confirmCloseMonthButton")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelCloseMonthButton")
            } message: {
                Text(FinanceCopy.closeMonthWarning)
            }
            .sheet(isPresented: $isEditingMoney) {
                EditMonthlyPlanView(plan: plan)
            }
            .sheet(isPresented: $isAddingCategory) {
                AddCategoryView(plan: plan)
            }
            .sheet(item: $categoryBeingEdited) { category in
                EditCategoryView(category: category)
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(isPresent: $categoryPendingDeletion),
                titleVisibility: .visible,
                presenting: categoryPendingDeletion
            ) { category in
                Button("Delete Category", role: .destructive) { delete(category) }
                    .accessibilityIdentifier("confirmDeleteCategoryButton")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelDeleteCategoryButton")
            } message: { category in
                Text(deletionMessage(for: category))
            }
            .alert("Could not delete", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section("MONTHLY MONEY") {
            money("Starting Money", summary.startingBalance, id: "summaryStartingMoney")
            moneyAddedRow
            money("Total Money", summary.totalMoney, id: "summaryTotalMoney")

            money("Spent", summary.totalSpent, id: "summarySpent")
            money("Money Remaining", summary.moneyRemaining, id: "summaryMoneyRemaining")

            money("Protected Money", summary.protectedAmount, id: "summaryProtectedMoney")
            LabeledContent("Safe to Spend") {
                Text(summary.safeToSpend.currencyText)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(summary.isProtectedMoneyAtRisk ? .red : .primary)
            }
            .accessibilityIdentifier("summarySafeToSpend")

            if summary.isProtectedMoneyAtRisk {
                Text("You have started spending money you meant to protect.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if plan.isClosed {
                Label(FinanceCopy.closedMonthNotice, systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("closedMonthNotice")
            } else {
                Button("Edit Starting & Protected Money") { isEditingMoney = true }
                    .accessibilityIdentifier("editPlanMoneyButton")
            }
        }
    }

    /// Signed once there is something to add, so it reads as money coming in
    /// rather than as a balance. The entry count is derived from the
    /// relationship, never stored.
    private var moneyAddedRow: some View {
        let count = plan.moneyAdded.count
        return LabeledContent {
            Text(count > 0 ? summary.moneyAdded.signedCurrencyText
                           : summary.moneyAdded.currencyText)
                .font(.body.monospacedDigit())
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Money Added")
                if count > 0 {
                    Text("\(count) \(count == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("summaryMoneyAdded")
    }

    private func money(_ label: String, _ amount: Decimal, id: String) -> some View {
        LabeledContent(label) {
            Text(amount.currencyText).font(.body.monospacedDigit())
        }
        .accessibilityIdentifier(id)
    }

    // MARK: - Budgets

    @ViewBuilder
    private var budgetsSection: some View {
        Section("BUDGETS") {
            if categories.isEmpty {
                Text("No categories yet. Add one to start budgeting.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(categories) { category in
                    CategoryBudgetRow(category: category)
                        .accessibilityIdentifier("categoryRow-\(category.name)")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !plan.isClosed { categoryBeingEdited = category }
                        }
                        .swipeActions(edge: .trailing) {
                            if !plan.isClosed {
                                Button(role: .destructive) {
                                    categoryPendingDeletion = category
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("swipeDeleteCategoryButton")
                                Button {
                                    categoryBeingEdited = category
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }
        }
    }

    /// Expenses whose category was deleted still spend real money, so they are
    /// shown rather than quietly dropped off this screen.
    /// Only appears when there is something to clean up -- a month with every
    /// expense categorised should not be nagged about it.
    @ViewBuilder
    private var uncategorizedSection: some View {
        let orphans = FinanceCalculator.uncategorizedExpenses(for: plan)
        if !orphans.isEmpty {
            Section("UNCATEGORIZED") {
                Button {
                    isShowingUncategorized = true
                } label: {
                    LabeledContent {
                        Text(FinanceCalculator.uncategorizedSpent(for: plan).currencyText)
                            .font(.body.monospacedDigit())
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uncategorized Spending")
                            Text("\(orphans.count) \(orphans.count == 1 ? "expense" : "expenses") with no budget")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("uncategorizedLink")
            }
        }
    }

    // MARK: - Deleting a category

    private var deletionTitle: String {
        guard let category = categoryPendingDeletion else { return "Delete Category?" }
        return "Delete \"\(category.name)\"?"
    }

    private func deletionMessage(for category: BudgetCategory) -> String {
        FinanceCopy.categoryDeletionWarning(expenseCount: category.expenses.count)
    }

    // MARK: - Month lifecycle

    /// Closing and starting the next month are separate actions on purpose: a
    /// month can be prepared before the current one is finished.
    private var monthActionsSection: some View {
        Section("MONTH") {
            Button("Start Next Month") { isStartingNextMonth = true }
                .accessibilityIdentifier("startNextMonthButton")

            if plan.isClosed {
                Label("Closed", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("monthClosedLabel")
            } else {
                Button("Close Month", role: .destructive) { isConfirmingClose = true }
                    .accessibilityIdentifier("closeMonthButton")
            }
        }
    }

    private func closeMonth() {
        do {
            try MonthlyPlanService.closePlan(plan, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ category: BudgetCategory) {
        do {
            try BudgetCategoryService.deleteCategory(category, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One category's budget, spending and progress.
struct CategoryBudgetRow: View {

    let category: BudgetCategory

    private var spent: Decimal { FinanceCalculator.spent(in: category) }
    private var remaining: Decimal { FinanceCalculator.remaining(in: category) }
    private var isOver: Bool { FinanceCalculator.isOverBudget(category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(category.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(spent.currencyText) of \(category.monthlyBudget.currencyText)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            // Clamped for the bar only. The figures above and below are exact.
            ProgressView(value: FinanceCalculator.displayProgress(for: category))
                .tint(isOver ? .red : .accentColor)

            Text(statusText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(isOver ? .red : .secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        FinanceCopy.budgetStatus(spent: spent, budget: category.monthlyBudget)
    }
}
