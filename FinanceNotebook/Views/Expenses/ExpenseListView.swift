import SwiftUI
import SwiftData

struct ExpenseListView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context

    @State private var isAddingExpense = false
    @State private var expensePendingDeletion: Expense?
    @State private var errorMessage: String?

    /// Newest first, grouped by day.
    private var groupedExpenses: [(date: Date, expenses: [Expense])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: plan.expenses) {
            calendar.startOfDay(for: $0.date)
        }
        return groups
            .map { (date: $0.key, expenses: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.expenses.isEmpty {
                    emptyState
                } else {
                    expenseList
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MonthSelectorButton(plan: plan)
                }
                if !plan.isClosed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingExpense = true
                        } label: {
                            Label("Add Expense", systemImage: "plus")
                        }
                        .accessibilityIdentifier("addExpenseButton")
                        .accessibilityLabel("Add Expense")
                    }
                }
            }
            .sheet(isPresented: $isAddingExpense) {
                AddExpenseView(plan: plan)
            }
            .confirmationDialog(
                "Delete Expense?",
                isPresented: Binding(isPresent: $expensePendingDeletion),
                titleVisibility: .visible,
                presenting: expensePendingDeletion
            ) { expense in
                Button("Delete", role: .destructive) { delete(expense) }
                    .accessibilityIdentifier("confirmDeleteFromListButton")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelDeleteFromListButton")
            } message: { _ in
                Text("This will permanently remove this expense.")
            }
            .alert(
                "Could not delete",
                isPresented: Binding(isPresent: $errorMessage)
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - List

    private var expenseList: some View {
        List {
            Section {
                EmptyView()
            } header: {
                Text(plan.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            ForEach(groupedExpenses, id: \.date) { group in
                Section(group.date.expenseSectionTitle) {
                    ForEach(group.expenses) { expense in
                        NavigationLink {
                            ExpenseDetailView(expense: expense)
                        } label: {
                            ExpenseRow(expense: expense)
                        }
                        .accessibilityIdentifier("expense-\(expense.merchant)")
                        .swipeActions(edge: .trailing) {
                            if !plan.isClosed {
                                // Asks first: a swipe must not destroy a record.
                                Button(role: .destructive) {
                                    expensePendingDeletion = expense
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("swipeDeleteExpenseButton")
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Expenses Yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Record your first purchase to start tracking where your money goes.")
        } actions: {
            if !plan.isClosed {
                Button("Add Expense") { isAddingExpense = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("emptyStateAddExpenseButton")
            }
        }
    }

    private func delete(_ expense: Expense) {
        do {
            try ExpenseService.deleteExpense(expense, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ExpenseRow: View {

    let expense: Expense

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.body)
                Text(expense.category?.name ?? "Uncategorized")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(expense.amount.currencyText)
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}
