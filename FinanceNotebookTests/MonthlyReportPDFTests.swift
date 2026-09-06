import XCTest
import SwiftData
import PDFKit
@testable import FinanceNotebook

/// The PDF is checked for the things that actually matter: that it is a real
/// PDF, that nothing is dropped when the content grows, and that it paginates
/// rather than clipping. Pixel comparisons would break on every font tweak and
/// prove nothing about whether the month is reported correctly.
final class MonthlyReportPDFTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400"), protectedAmount: dec("1000"),
            context: context
        )
    }

    override func tearDown() {
        plan = nil; context = nil; container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    private func report() -> MonthlyReportSnapshot {
        MonthlyReportBuilder.makeReport(for: plan, context: context)
    }

    private func render(_ level: ReportDetailLevel) -> Data {
        MonthlyReportPDFRenderer.render(report: report(), level: level)
    }

    /// A PDF file begins with "%PDF-".
    private func assertIsPDF(_ data: Data, _ message: String, line: UInt = #line) {
        XCTAssertGreaterThan(data.count, 1000, "\(message): suspiciously small", line: line)
        let header = data.prefix(5)
        XCTAssertEqual(String(decoding: header, as: UTF8.self), "%PDF-",
                       "\(message): not a PDF", line: line)
    }

    private func pageCount(_ data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    /// All the text in the document, for checking a section is present or
    /// absent without caring where it landed.
    private func text(in data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    @discardableResult
    private func seedTypicalMonth() throws -> BudgetCategory {
        let eatingOut = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(3), merchant: "Chipotle",
            note: "Lunch after class", category: eatingOut, plan: plan, context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100"), date: date(5), source: "Refund",
            note: "Returned headphones", plan: plan, context: context
        )
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(7), note: "Cook at home more.", context: context
        )
        try ReviewService.saveMonthlyReview(
            for: plan, spentMoreThanExpected: "A little.", avoidablePurchase: nil,
            worthwhilePurchase: "The winter coat.", changeNextMonth: "Plan meals.",
            additionalNotes: nil, context: context
        )
        return eatingOut
    }

    // MARK: - The three levels

    func testAllThreeLevelsProduceRealPDFs() throws {
        try seedTypicalMonth()
        for level in ReportDetailLevel.allCases {
            assertIsPDF(render(level), "\(level.displayName) report")
            XCTAssertGreaterThanOrEqual(pageCount(render(level)), 1)
        }
    }

    func testSummaryOmitsTheDeeperSections() throws {
        try seedTypicalMonth()
        let content = text(in: render(.summary))

        XCTAssertTrue(content.contains("FINANCIAL SUMMARY"))
        XCTAssertTrue(content.contains("CATEGORIES"))
        XCTAssertFalse(content.contains("MONEY ADDED"), "Summary should not carry Money Added")
        XCTAssertFalse(content.contains("EXPENSES"), "Summary should not carry the ledger")
        XCTAssertFalse(content.contains("WEEKLY CHECK-INS"))
        XCTAssertFalse(content.contains("MONTHLY REFLECTION"))
    }

    func testStandardAddsMoneyAddedAndReflectionButNotTheLedger() throws {
        try seedTypicalMonth()
        let content = text(in: render(.standard))

        XCTAssertTrue(content.contains("FINANCIAL SUMMARY"))
        XCTAssertTrue(content.contains("MONEY ADDED"))
        XCTAssertTrue(content.contains("MONTHLY REFLECTION"))
        XCTAssertFalse(content.contains("EXPENSES"),
                       "Standard must not carry the whole ledger")
        XCTAssertFalse(content.contains("WEEKLY CHECK-INS"))
    }

    func testFullCarriesEverything() throws {
        try seedTypicalMonth()
        let content = text(in: render(.full))

        for section in ["FINANCIAL SUMMARY", "CATEGORIES", "MONEY ADDED",
                        "EXPENSES", "WEEKLY CHECK-INS", "MONTHLY REFLECTION"] {
            XCTAssertTrue(content.contains(section), "Full report is missing \(section)")
        }
        XCTAssertTrue(content.contains("Chipotle"), "The expense is missing from the ledger")
        XCTAssertTrue(content.contains("Refund"))
        XCTAssertTrue(content.contains("Cook at home more."))
        XCTAssertTrue(content.contains("The winter coat."))
    }

    // MARK: - Content correctness

    func testTheHeaderNamesTheMonthAndTheLevel() throws {
        try seedTypicalMonth()
        let content = text(in: render(.full))
        XCTAssertTrue(content.contains("FINANCE NOTEBOOK"))
        XCTAssertTrue(content.contains("September 2026"))
        XCTAssertTrue(content.contains("Full Report"))
    }

    func testAnOpenMonthSaysSoAndAClosedOneSaysSo() throws {
        try seedTypicalMonth()
        XCTAssertTrue(text(in: render(.summary))
                        .contains("Generated while the month was still open."))

        try MonthlyPlanService.closePlan(plan, context: context)
        XCTAssertTrue(text(in: render(.summary)).contains("This month is closed."))
    }

    func testAwkwardDecimalsAppearExactlyInThePDF() throws {
        let misc = try BudgetCategoryService.createCategory(
            name: "Misc", monthlyBudget: dec("5000"), type: .flexible,
            plan: plan, context: context
        )
        for (index, amount) in ["0.01", "0.10", "14.72", "42.18", "100.00"].enumerated() {
            try ExpenseService.createExpense(
                amount: dec(amount), date: date(index + 1), merchant: "M\(index)",
                note: nil, category: misc, plan: plan, context: context
            )
        }

        let content = text(in: render(.full))
        for amount in ["0.01", "0.10", "14.72", "42.18", "100.00", "2,400.00"] {
            XCTAssertTrue(content.contains(amount), "\(amount) is missing or malformed in the PDF")
        }
        XCTAssertFalse(content.contains("$-"), "Malformed negative currency in the PDF")
        XCTAssertFalse(content.contains("$+"), "Malformed signed currency in the PDF")
    }

    func testOverspendingIsShownNotHidden() throws {
        let eatingOut = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("235"), date: date(4), merchant: "Various",
            note: nil, category: eatingOut, plan: plan, context: context
        )

        let content = text(in: render(.summary))
        XCTAssertTrue(content.contains("35.00 over budget"),
                      "The report hid an over-budget category")
    }

    // MARK: - Pagination

    /// A month with a lot of spending must produce a longer document, not a
    /// clipped one.
    func testAHundredAndFiftyExpensesPaginate() throws {
        let misc = try BudgetCategoryService.createCategory(
            name: "Misc", monthlyBudget: dec("50000"), type: .flexible,
            plan: plan, context: context
        )
        for index in 0..<150 {
            try ExpenseService.createExpense(
                amount: dec("12.34"), date: date((index % 28) + 1),
                merchant: "Merchant number \(index)", note: nil,
                category: misc, plan: plan, context: context
            )
        }

        let data = render(.full)
        assertIsPDF(data, "150-expense report")
        XCTAssertGreaterThan(pageCount(data), 1, "The long report did not paginate")

        let content = text(in: data)
        XCTAssertTrue(content.contains("Merchant number 0"), "The first expense was dropped")
        XCTAssertTrue(content.contains("Merchant number 149"), "The last expense was dropped")
        XCTAssertEqual(report().expenses.count, 150)
    }

    /// Page numbers should know the total, which needs the two-pass layout.
    func testPageFootersCountTheWholeDocument() throws {
        let misc = try BudgetCategoryService.createCategory(
            name: "Misc", monthlyBudget: dec("50000"), type: .flexible,
            plan: plan, context: context
        )
        for index in 0..<120 {
            try ExpenseService.createExpense(
                amount: dec("9.99"), date: date((index % 28) + 1),
                merchant: "Item \(index)", note: nil,
                category: misc, plan: plan, context: context
            )
        }

        let data = render(.full)
        let total = pageCount(data)
        XCTAssertGreaterThan(total, 1)
        XCTAssertTrue(text(in: data).contains("Page 1 of \(total)"),
                      "The footer did not report the true page count")
    }

    /// A long reflection is the user's writing and must not be cut to fit.
    func testALongReflectionWrapsAcrossPagesWithoutTruncation() throws {
        let sentence = "This month I spent far more on eating out than I meant to, "
            + "mostly on days when I had not planned anything and it was easier to buy lunch. "
        let longAnswer = String(repeating: sentence, count: 60)

        try ReviewService.saveMonthlyReview(
            for: plan, spentMoreThanExpected: longAnswer, avoidablePurchase: nil,
            worthwhilePurchase: nil, changeNextMonth: "Plan meals on Sunday.",
            additionalNotes: nil, context: context
        )

        let data = render(.standard)
        assertIsPDF(data, "long reflection report")
        XCTAssertGreaterThan(pageCount(data), 1, "A very long reflection did not paginate")

        let content = text(in: data)
        XCTAssertTrue(content.contains("Plan meals on Sunday."),
                      "The answer after the long one was lost")
        // The tail of the long answer must survive the page breaks.
        XCTAssertTrue(content.contains("it was easier to buy lunch."),
                      "The long reflection was truncated")
    }

    // MARK: - Awkward months

    func testAnEmptyMonthExportsAtEveryLevel() throws {
        for level in ReportDetailLevel.allCases {
            let data = render(level)
            assertIsPDF(data, "empty month, \(level.displayName)")
            XCTAssertEqual(pageCount(data), 1)
        }

        let content = text(in: render(.full))
        XCTAssertTrue(content.contains("No categories this month."))
        XCTAssertTrue(content.contains("No money added this month."))
        XCTAssertTrue(content.contains("No expenses this month."))
        XCTAssertTrue(content.contains("No weekly check-ins recorded."))
        XCTAssertTrue(content.contains("No monthly reflection recorded."))
    }

    func testAClosedMonthExportsAndStaysClosed() throws {
        try seedTypicalMonth()
        try MonthlyPlanService.closePlan(plan, context: context)

        let data = render(.full)
        assertIsPDF(data, "closed month report")
        XCTAssertTrue(plan.isClosed, "Exporting reopened the month")

        // And it is still read-only afterwards.
        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: dec("1"), date: date(9), merchant: "Nope", note: nil,
                category: plan.categories.first, plan: plan, context: context
            )
        )
    }

    // MARK: - Files

    func testTheFileNameNamesTheMonthAndLevel() throws {
        let snapshot = report()
        XCTAssertEqual(
            MonthlyReportPDFRenderer.fileName(for: snapshot, level: .summary),
            "Finance-Notebook-2026-09-Summary.pdf"
        )
        XCTAssertEqual(
            MonthlyReportPDFRenderer.fileName(for: snapshot, level: .full),
            "Finance-Notebook-2026-09-Full.pdf"
        )
    }

    func testWritingProducesAReadableFileAndOverwritesOnReExport() throws {
        try seedTypicalMonth()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "report-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try MonthlyReportPDFRenderer.write(
            report: report(), level: .full, directory: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        assertIsPDF(try Data(contentsOf: url), "written report")
        XCTAssertEqual(url.lastPathComponent, "Finance-Notebook-2026-09-Full.pdf")

        // Exporting the same month again replaces the file rather than piling up.
        let again = try MonthlyReportPDFRenderer.write(
            report: report(), level: .full, directory: directory
        )
        XCTAssertEqual(again, url)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents.count, 1, "Re-exporting left a second file behind")
    }
}
