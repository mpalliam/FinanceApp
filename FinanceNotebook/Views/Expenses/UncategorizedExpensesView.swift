import SwiftUI
import SwiftData

/// Cleaning up expenses whose category was deleted.
///
/// Deleting a category deliberately keeps its spending rather than destroying
/// it, which leaves those expenses with no category. Putting them back one at a
/// time through the edit screen works but is tedious enough that it does not
/// get done, so the money sits outside every budget. This is the screen that
/// makes it a minute's work.
struct UncategorizedExpensesView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<UUID> = []
    @State private var isChoosingCategory = false
    @State private var errorMessage: String?

    /// Newest first, matching Transactions. A cleanup list is read the same way
    /// as the list it came from.
    private var expenses: [Expense] {
        FinanceCalculator.uncategorizedExpenses(for: plan)
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    private var total: Decimal {
        FinanceCalculator.uncategorizedSpent(for: plan)
    }

    private var categories: [BudgetCategory] {
        plan.categories.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var selectedExpenses: [Expense] {
        expenses.filter { selection.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        List {
            if expenses.isEmpty {
                allCaughtUp
            } else {
                summarySection
                if plan.isClosed { closedNotice }
                expenseSection
            }
        }
        .navigationTitle("Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("uncategorizedView")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("doneUncategorizedButton")
            }
            if !expenses.isEmpty && !plan.isClosed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selection.isEmpty ? "Select All" : "Deselect All") {
                        selection = selection.isEmpty ? Set(expenses.map(\.id)) : []
                    }
                    .accessibilityIdentifier("toggleSelectAllButton")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isChoosingCategory = true
                    } label: {
                        Text(assignButtonTitle)
                    }
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("assignCategoryButton")
                }
            }
        }
        // A sheet rather than a confirmationDialog. Presenting a dialog from a
        // bottom-bar item popped this whole screen back to Plan, and a dialog's
        // buttons do not carry their accessibility identifiers either. A sheet
        // is predictable, and it copes with more than a handful of categories.
        .sheet(isPresented: $isChoosingCategory) {
            categoryPicker
        }
        .alert("Couldn't Assign Category",
               isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var categoryPicker: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            assign(to: category)
                        } label: {
                            LabeledContent(category.name) {
                                Text(category.monthlyBudget.currencyText)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("assignTo-\(category.name)")
                    }
                } footer: {
                    Text("\(selection.count) \(selection.count == 1 ? "expense" : "expenses") will be moved. Nothing else about them changes.")
                }
            }
            .navigationTitle("Assign to Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isChoosingCategory = false }
                        .accessibilityIdentifier("cancelAssignButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var assignButtonTitle: String {
        selection.isEmpty
            ? "Assign Category"
            : "Assign \(selection.count) \(selection.count == 1 ? "Expense" : "Expenses")"
    }

    // MARK: - Sections

    private var allCaughtUp: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("All Caught Up").font(.headline)
                Text("Every expense in this month has a category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("uncategorizedEmptyState")
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Expenses", value: "\(expenses.count)")
                .accessibilityIdentifier("uncategorizedCount")
            LabeledContent("Spent", value: total.currencyText)
                .accessibilityIdentifier("uncategorizedTotal")
        } footer: {
            if !plan.isClosed && categories.isEmpty {
                Text("Add a category on the Plan screen before assigning these.")
            }
        }
    }

    private var closedNotice: some View {
        Section {
            Label(FinanceCopy.closedMonthNotice, systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("closedMonthNotice")
        }
    }

    private var expenseSection: some View {
        Section {
            ForEach(expenses) { expense in
                row(expense)
            }
        } header: {
            Text(plan.isClosed ? "EXPENSES" : "SELECT EXPENSES")
        }
    }

    private func row(_ expense: Expense) -> some View {
        // A closed month can be read but not tidied, so rows stop being
        // selectable rather than silently failing on assign.
        Button {
            guard !plan.isClosed else { return }
            if selection.contains(expense.id) {
                selection.remove(expense.id)
            } else {
                selection.insert(expense.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if !plan.isClosed {
                    Image(systemName: selection.contains(expense.id)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(expense.id) ? Color.accentColor : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.merchant).foregroundStyle(.primary)
                    Text(expense.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = expense.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(expense.amount.currencyText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .disabled(plan.isClosed)
        .accessibilityIdentifier("uncategorized-\(expense.merchant)")
    }

    // MARK: - Assigning

    private func assign(to category: BudgetCategory) {
        let chosen = selectedExpenses
        isChoosingCategory = false
        do {
            try ExpenseService.assignCategory(to: chosen, category: category, context: context)
            selection = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
