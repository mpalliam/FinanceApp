import SwiftUI
import SwiftData

/// Edits a category in place, so the expenses already assigned to it stay
/// assigned. Renaming a category is not a reason to build a new one.
struct EditCategoryView: View {

    let category: BudgetCategory

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

                if !category.expenses.isEmpty {
                    Section {
                        Text("\(category.expenses.count) expense\(category.expenses.count == 1 ? "" : "s") stay assigned to this category.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Category")
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
        .onAppear {
            name = category.name
            budgetText = "\(category.monthlyBudget)"
            type = category.type
        }
    }

    private func save() {
        let trimmed = budgetText.trimmingCharacters(in: .whitespaces)
        let budget = trimmed.isEmpty ? Decimal.zero : Decimal(string: trimmed, locale: .current)

        guard let budget else {
            errorMessage = "Enter the budget as a number."
            return
        }

        do {
            try BudgetCategoryService.updateCategory(
                category,
                name: name,
                monthlyBudget: budget,
                type: type,
                context: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
