import SwiftUI
import SwiftData

/// Creates a month from scratch: the first one, a backfilled older one, or one
/// skipped ahead. `Start Next Month` is the faster path for the usual case.
struct CreateMonthlyPlanView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MonthSelection.self) private var selection

    @State private var month: Int
    @State private var year: Int
    @State private var startingText = ""
    @State private var protectedText = ""
    @State private var errorMessage: String?

    init() {
        let calendar = Calendar.current
        _month = State(initialValue: calendar.component(.month, from: Date()))
        _year = State(initialValue: calendar.component(.year, from: Date()))
    }

    private var years: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 2)...(thisYear + 2))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Month") {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { value in
                            Text(Self.monthName(value)).tag(value)
                        }
                    }
                    .accessibilityIdentifier("monthPicker")

                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    .accessibilityIdentifier("yearPicker")
                }

                Section("Starting Money") {
                    TextField("0.00", text: $startingText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("startingMoneyField")
                        .accessibilityLabel("Starting Money")
                }

                Section("Protected Money") {
                    TextField("0.00", text: $protectedText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("protectedMoneyField")
                        .accessibilityLabel("Protected Money")
                }

                Section {
                    Text("Protected money is money you intend not to spend. You can add categories once the month exists.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Start a Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .accessibilityIdentifier("createMonthButton")
                }
            }
            .alert("Cannot Create", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    static func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        components.year = 2000
        guard let date = Calendar.current.date(from: components) else { return "\(month)" }
        return date.formatted(.dateTime.month(.wide))
    }

    private func create() {
        let starting = Decimal(string: startingText.trimmingCharacters(in: .whitespaces),
                               locale: .current) ?? .zero
        let protected = Decimal(string: protectedText.trimmingCharacters(in: .whitespaces),
                                locale: .current) ?? .zero

        do {
            // Creation always goes through the service, so the one-plan-per-month
            // rule holds however the month was reached.
            let plan = try MonthlyPlanService.createPlan(
                month: month, year: year,
                startingBalance: starting, protectedAmount: protected,
                context: context
            )
            selection.monthKey = plan.monthKey
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
