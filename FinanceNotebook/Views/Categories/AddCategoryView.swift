import SwiftUI
import SwiftData

/// Minimal category creation. It exists only because adding an expense needs a
/// category to point at; the real budgeting interface comes later.
struct AddCategoryView: View {

    let plan: MonthlyPlan
    var onCreate: (BudgetCategory) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var budgetText = ""
    @State private var type: CategoryType = .flexible
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Eating Out", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("categoryNameField")
                        .accessibilityLabel("Category Name")
                }

                Section("Monthly Budget") {
                    TextField("0.00", text: $budgetText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("categoryBudgetField")
                        .accessibilityLabel("Monthly Budget")
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(CategoryType.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("categoryTypePicker")
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Category") { save() }
                        .accessibilityIdentifier("saveCategoryButton")
                }
            }
            .alert("Cannot Save", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        let trimmed = budgetText.trimmingCharacters(in: .whitespaces)
        // An empty budget means zero, which is allowed.
        let budget = trimmed.isEmpty ? Decimal.zero : Decimal(string: trimmed, locale: .current)

        guard let budget else {
            errorMessage = BudgetCategoryError.negativeBudget.localizedDescription
            return
        }

        do {
            let category = try BudgetCategoryService.createCategory(
                name: name,
                monthlyBudget: budget,
                type: type,
                plan: plan,
                context: context
            )
            onCreate(category)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
