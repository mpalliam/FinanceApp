import SwiftUI
import SwiftData

/// The month, written up.
///
/// Everything here comes from one MonthlyReportSnapshot, and so does the PDF.
/// Two code paths doing their own arithmetic is how a screen and a document end
/// up disagreeing by a cent, which would make both untrustworthy.
///
/// Opening or exporting a report changes nothing. It reads the month; it never
/// writes to it, closed or open.
struct MonthlyReportView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context

    @State private var level: ReportDetailLevel = .summary
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    private var report: MonthlyReportSnapshot {
        MonthlyReportBuilder.makeReport(for: plan, context: context)
    }

    var body: some View {
        List {
            levelSection
            summarySection
            categorySection

            if level.includesMoneyAdded { moneyAddedSection }
            if level.includesExpenseLedger { expenseSection }
            if level.includesWeeklyReviews { weeklyReviewSection }
            if level.includesReflection { reflectionSection }

            exportSection
        }
        .navigationTitle("Monthly Report")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("monthlyReportView")
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Couldn't Create PDF", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Level

    private var levelSection: some View {
        Section {
            Picker("Detail", selection: $level) {
                ForEach(ReportDetailLevel.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reportLevelPicker")
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.monthTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(report.isClosed ? "Closed" : "In Progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textCase(nil)
            .accessibilityIdentifier("reportHeader")
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section("FINANCIAL SUMMARY") {
            money("Starting Money", report.summary.startingBalance.currencyText)
            money("Money Added", report.moneyAdded.isEmpty
                  ? report.summary.moneyAdded.currencyText
                  : report.summary.moneyAdded.signedCurrencyText)
            money("Total Money", report.summary.totalMoney.currencyText)
            money("Total Spent", report.summary.totalSpent.currencyText)
            money("Money Remaining", report.summary.moneyRemaining.currencyText)
            money("Protected Money", report.summary.protectedAmount.currencyText)
            money("Safe to Spend", report.summary.safeToSpend.currencyText,
                  emphasised: true,
                  warning: report.summary.isProtectedMoneyAtRisk)
        }
        .accessibilityIdentifier("reportFinancialSummary")
    }

    private var categorySection: some View {
        Section("CATEGORIES") {
            if report.categories.isEmpty && report.uncategorized == nil {
                Text("No categories this month.").foregroundStyle(.secondary)
            }

            ForEach(report.categories) { category in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(category.name) {
                        Text("\(category.spent.currencyText) of \(category.budget.currencyText)")
                            .font(.subheadline.monospacedDigit())
                    }
                    Text(statusText(for: category))
                        .font(.caption)
                        .foregroundStyle(category.isOverBudget ? .red : .secondary)
                }
                .accessibilityIdentifier("reportCategory-\(category.name)")
            }

            if let uncategorized = report.uncategorized {
                LabeledContent("Uncategorized") {
                    Text(uncategorized.spent.currencyText)
                        .font(.subheadline.monospacedDigit())
                }
                .accessibilityIdentifier("reportUncategorized")
            }
        }
        .accessibilityIdentifier("reportCategorySummary")
    }

    private var moneyAddedSection: some View {
        Section("MONEY ADDED") {
            if report.moneyAdded.isEmpty {
                Text("No money added this month.").foregroundStyle(.secondary)
            }
            ForEach(report.moneyAdded) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(entry.source) {
                        Text(entry.amount.signedCurrencyText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = entry.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("reportMoneyAdded")
    }

    private var expenseSection: some View {
        Section("EXPENSES") {
            if report.expenses.isEmpty {
                Text("No expenses this month.").foregroundStyle(.secondary)
            }
            ForEach(report.expenses) { expense in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(expense.merchant) {
                        Text("-\(expense.amount.currencyText)")
                            .font(.subheadline.monospacedDigit())
                    }
                    Text("\(expense.date.formatted(.dateTime.month(.abbreviated).day()))  ·  \(expense.categoryName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = expense.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("reportExpenseLedger")
    }

    private var weeklyReviewSection: some View {
        Section("WEEKLY CHECK-INS") {
            if report.weeklyReviews.isEmpty {
                Text("No weekly check-ins recorded.").foregroundStyle(.secondary)
            }
            ForEach(report.weeklyReviews) { review in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week of \(review.weekStartDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.medium))
                    Text(review.note ?? "No note.")
                        .font(.footnote)
                        .foregroundStyle(review.note == nil ? .secondary : .primary)
                }
            }
        }
        .accessibilityIdentifier("reportWeeklyReviews")
    }

    private var reflectionSection: some View {
        Section("MONTHLY REFLECTION") {
            if let reflection = report.reflection, !reflection.isEmpty {
                ForEach(reflection.answers) { answer in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(answer.question)
                            .font(.subheadline.weight(.medium))
                        Text(answer.answer)
                            .font(.footnote)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("No monthly reflection recorded.").foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("reportMonthlyReflection")
    }

    private var exportSection: some View {
        Section {
            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("exportPDFButton")
        } footer: {
            Text("A PDF is a readable copy of this month. It is not a backup.")
        }
    }

    // MARK: - Helpers

    /// No per-row identifier: an identifier on the enclosing Section overrides
    /// the ones inside it, so every row here reports the section's. Rows are
    /// found by their label instead, which is what actually reaches the
    /// accessibility tree.
    private func money(_ label: String, _ value: String,
                       emphasised: Bool = false, warning: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(emphasised ? .body.monospacedDigit().weight(.semibold)
                                 : .body.monospacedDigit())
                .foregroundStyle(warning ? .red : .primary)
        }
    }

    private func statusText(for category: MonthlyReportSnapshot.CategoryRow) -> String {
        FinanceCopy.budgetStatus(spent: category.spent, budget: category.budget)
    }

    private func exportPDF() {
        do {
            shareURL = try MonthlyReportPDFRenderer.write(report: report, level: level)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// So a URL can drive `.sheet(item:)`, which keeps the file and the sheet's
/// lifetime tied together.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
