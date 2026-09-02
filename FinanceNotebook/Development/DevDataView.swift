import SwiftUI
import SwiftData

/// Temporary screen for exercising the data layer. This is not the real UI and
/// will be replaced in a later milestone.
struct DevDataView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\MonthlyPlan.year), SortDescriptor(\MonthlyPlan.month)])
    private var plans: [MonthlyPlan]

    /// The plan the sample buttons act on.
    private var samplePlan: MonthlyPlan? {
        plans.first { $0.month == 9 && $0.year == 2026 }
    }

    var body: some View {
        NavigationStack {
            List {
                actionsSection

                if plans.isEmpty {
                    Section {
                        Text("No saved data yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(plans) { plan in
                    planSection(plan)
                }
            }
            .navigationTitle("Data Layer Test")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section("Create sample data") {
            Button("1. September 2026 plan") { createSamplePlan() }

            Button("2. \"Eating Out\" category") { createSampleCategory() }
                .disabled(samplePlan == nil)

            Button("3. Chipotle expense") { createSampleExpense() }
                .disabled(sampleCategory == nil)

            Button("4. Refund money added") { createSampleMoneyAdded() }
                .disabled(samplePlan == nil)

            Button("Delete everything", role: .destructive) { deleteEverything() }
                .disabled(plans.isEmpty)
        }
    }

    private var sampleCategory: BudgetCategory? {
        samplePlan?.categories.first { $0.name == "Eating Out" }
    }

    private func createSamplePlan() {
        // Only one plan may exist per month/year, and SwiftData cannot express a
        // uniqueness constraint across two attributes, so check before inserting.
        guard samplePlan == nil else { return }

        let plan = MonthlyPlan(
            month: 9,
            year: 2026,
            startingBalance: Decimal(string: "2400.00") ?? .zero,
            protectedAmount: Decimal(string: "1000.00") ?? .zero
        )
        context.insert(plan)
        save()
    }

    private func createSampleCategory() {
        guard let plan = samplePlan, sampleCategory == nil else { return }

        let category = BudgetCategory(
            name: "Eating Out",
            monthlyBudget: Decimal(string: "200.00") ?? .zero,
            type: .flexible,
            plan: plan
        )
        context.insert(category)
        save()
    }

    private func createSampleExpense() {
        guard let plan = samplePlan, let category = sampleCategory else { return }

        let expense = Expense(
            amount: Decimal(string: "14.72") ?? .zero,
            date: date(day: 2, month: 9, year: 2026),
            merchant: "Chipotle",
            category: category,
            plan: plan
        )
        context.insert(expense)
        save()
    }

    private func createSampleMoneyAdded() {
        guard let plan = samplePlan else { return }

        let entry = MoneyAddedEntry(
            amount: Decimal(string: "100.00") ?? .zero,
            date: date(day: 15, month: 9, year: 2026),
            source: "Refund",
            plan: plan
        )
        context.insert(entry)
        save()
    }

    private func deleteEverything() {
        // Deleting the plans cascades to their categories, expenses and additions.
        for plan in plans {
            context.delete(plan)
        }
        save()
    }

    /// SwiftData autosaves, but saving explicitly makes the relaunch test
    /// unambiguous.
    private func save() {
        do {
            try context.save()
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func date(day: Int, month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Display

    @ViewBuilder
    private func planSection(_ plan: MonthlyPlan) -> some View {
        Section(plan.displayTitle) {
            row("Starting balance", plan.startingBalance)
            row("Protected", plan.protectedAmount)
            LabeledContent("Closed", value: plan.isClosed ? "Yes" : "No")

            ForEach(plan.categories) { category in
                LabeledContent(
                    "\(category.name) (\(category.type.displayName))",
                    value: currency(category.monthlyBudget)
                )
            }

            ForEach(plan.expenses) { expense in
                LabeledContent(
                    "\(expense.merchant) - \(expense.category?.name ?? "Uncategorized")",
                    value: "-\(currency(expense.amount))"
                )
            }

            ForEach(plan.moneyAdded) { entry in
                LabeledContent(entry.source, value: "+\(currency(entry.amount))")
            }
        }
    }

    private func row(_ label: String, _ amount: Decimal) -> some View {
        LabeledContent(label, value: currency(amount))
    }

    private func currency(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }
}

#Preview {
    DevDataView()
        .modelContainer(
            for: [MonthlyPlan.self, BudgetCategory.self, Expense.self, MoneyAddedEntry.self],
            inMemory: true
        )
}
