import SwiftUI
import SwiftData

/// The editable fields of an expense, shared by Add and Edit so the two screens
/// cannot drift apart.
struct ExpenseFormFields {
    var amountText: String = ""
    var merchant: String = ""
    var note: String = ""
    var date: Date = Date()
    var category: BudgetCategory?

    /// nil when the text is not a number the user could have meant.
    var amount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: .current)
    }
}

struct ExpenseFormView: View {

    let plan: MonthlyPlan
    @Binding var fields: ExpenseFormFields

    @State private var isAddingCategory = false

    private var categories: [BudgetCategory] {
        plan.categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section("Amount") {
                TextField("0.00", text: $fields.amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                    .accessibilityIdentifier("amountField")
                    .accessibilityLabel("Amount")
            }

            Section("Merchant") {
                TextField("Chipotle", text: $fields.merchant)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("merchantField")
                    .accessibilityLabel("Merchant")
            }

            Section("Category") {
                if categories.isEmpty {
                    noCategories
                } else {
                    Picker("Category", selection: $fields.category) {
                        Text("Select").tag(BudgetCategory?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(BudgetCategory?.some(category))
                        }
                    }
                    .accessibilityIdentifier("categoryPicker")

                    Button("New Category") { isAddingCategory = true }
                        .accessibilityIdentifier("newCategoryButton")
                }
            }

            Section("Date") {
                DatePicker(
                    "Date",
                    selection: $fields.date,
                    in: dateRange,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("dateField")
            }

            Section("Note") {
                TextField("Optional", text: $fields.note, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("noteField")
                    .accessibilityLabel("Note")
            }
        }
        .sheet(isPresented: $isAddingCategory) {
            AddCategoryView(plan: plan) { created in
                fields.category = created
            }
        }
    }

    /// Confines the picker to the plan's own month. ExpenseService still
    /// validates, because a restricted picker is a convenience, not a guarantee.
    private var dateRange: ClosedRange<Date> {
        guard let interval = plan.monthInterval else {
            return Date.distantPast...Date.distantFuture
        }
        return interval.start...interval.end.addingTimeInterval(-1)
    }

    private var noCategories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Categories")
                .font(.headline)
            Text("Create a category before adding an expense.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add Category") { isAddingCategory = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("formAddCategoryButton")
        }
        .padding(.vertical, 4)
    }
}
