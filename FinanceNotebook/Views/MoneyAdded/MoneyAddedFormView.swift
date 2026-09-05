import SwiftUI
import SwiftData

/// The editable fields of a Money Added entry, shared by Add and Edit so the
/// two screens cannot drift apart.
struct MoneyAddedFormFields {
    var amountText: String = ""
    var source: String = ""
    var note: String = ""
    var date: Date = Date()

    /// nil when the text is not a number the user could have meant.
    var amount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: .current)
    }
}

struct MoneyAddedFormView: View {

    let plan: MonthlyPlan
    @Binding var fields: MoneyAddedFormFields

    var body: some View {
        Form {
            Section("Amount") {
                TextField("0.00", text: $fields.amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                    .accessibilityIdentifier("moneyAmountField")
                    .accessibilityLabel("Amount")
            }

            Section("Source") {
                TextField("Refund", text: $fields.source)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("moneySourceField")
                    .accessibilityLabel("Source")
            }

            Section("Date") {
                DatePicker(
                    "Date",
                    selection: $fields.date,
                    in: dateRange,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("moneyDateField")
            }

            Section("Note") {
                TextField("Optional", text: $fields.note, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("moneyNoteField")
                    .accessibilityLabel("Note")
            }

            Section {
                Text("Money Added is extra money that became available this month — a refund, a reimbursement, money from family. It is not income and not a paycheck.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Confines the picker to the plan's own month. MoneyAddedService still
    /// validates, because a restricted picker is a convenience, not a guarantee.
    private var dateRange: ClosedRange<Date> {
        guard let interval = plan.monthInterval else {
            return Date.distantPast...Date.distantFuture
        }
        return interval.start...interval.end.addingTimeInterval(-1)
    }
}
