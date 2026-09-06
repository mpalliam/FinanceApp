import XCTest
import SwiftData
@testable import FinanceNotebook

final class MonthlyReportBuilderTests: XCTestCase {

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

    private func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func report() -> MonthlyReportSnapshot {
        MonthlyReportBuilder.makeReport(for: plan, context: context)
    }

    @discardableResult
    private func category(_ name: String, budget: String,
                          type: CategoryType = .flexible) throws -> BudgetCategory {
        try BudgetCategoryService.createCategory(
            name: name, monthlyBudget: dec(budget), type: type, plan: plan, context: context
        )
    }

    @discardableResult
    private func expense(_ amount: String, _ merchant: String, on day: Int,
                         in category: BudgetCategory?, note: String? = nil) throws -> Expense {
        try ExpenseService.createExpense(
            amount: dec(amount), date: date(day), merchant: merchant,
            note: note, category: category, plan: plan, context: context
        )
    }

    @discardableResult
    private func moneyAdded(_ amount: String, _ source: String, on day: Int,
                            note: String? = nil) throws -> MoneyAddedEntry {
        try MoneyAddedService.createEntry(
            amount: dec(amount), date: date(day), source: source,
            note: note, plan: plan, context: context
        )
    }

    // MARK: - Financial summary

    func testFinancialSummaryComesFromTheCalculator() throws {
        let eatingOut = try category("Eating Out", budget: "700")
        try expense("624", "Various", on: 4, in: eatingOut)
        try moneyAdded("100", "Refund", on: 15)

        let summary = report().summary
        XCTAssertEqual(summary.startingBalance, dec("2400"))
        XCTAssertEqual(summary.moneyAdded, dec("100"))
        XCTAssertEqual(summary.totalMoney, dec("2500"))
        XCTAssertEqual(summary.totalSpent, dec("624"))
        XCTAssertEqual(summary.moneyRemaining, dec("1876"))
        XCTAssertEqual(summary.protectedAmount, dec("1000"))
        XCTAssertEqual(summary.safeToSpend, dec("876"))
    }

    /// The report must show overspending as it is.
    func testNegativeSafeToSpendIsReportedNotClamped() throws {
        let eatingOut = try category("Eating Out", budget: "2000")
        try expense("1550", "Various", on: 4, in: eatingOut)

        XCTAssertEqual(report().summary.safeToSpend, dec("-150"))
        XCTAssertTrue(report().summary.isProtectedMoneyAtRisk)
    }

    func testMonthIdentityAndClosedState() throws {
        XCTAssertEqual(report().month, 9)
        XCTAssertEqual(report().year, 2026)
        XCTAssertEqual(report().monthTitle, plan.displayTitle)
        XCTAssertFalse(report().isClosed)

        try MonthlyPlanService.closePlan(plan, context: context)
        XCTAssertTrue(report().isClosed)
    }

    // MARK: - Categories

    func testCategoryRowsCoverUnderOverAndZeroBudget() throws {
        let under = try category("Groceries", budget: "300")
        let over = try category("Eating Out", budget: "200")
        let zero = try category("Misc", budget: "0")
        try expense("267", "Fry's", on: 3, in: under)
        try expense("215", "Chipotle", on: 4, in: over)
        try expense("20", "Something", on: 5, in: zero)

        let rows = report().categories
        XCTAssertEqual(rows.map(\.name), ["Eating Out", "Groceries", "Misc"],
                       "Category rows should be alphabetical so reports are stable")

        let groceries = try XCTUnwrap(rows.first { $0.name == "Groceries" })
        XCTAssertEqual(groceries.spent, dec("267"))
        XCTAssertEqual(groceries.remaining, dec("33"))
        XCTAssertFalse(groceries.isOverBudget)

        let eatingOut = try XCTUnwrap(rows.first { $0.name == "Eating Out" })
        XCTAssertEqual(eatingOut.remaining, dec("-15"), "Over budget must not be clamped")
        XCTAssertTrue(eatingOut.isOverBudget)

        let misc = try XCTUnwrap(rows.first { $0.name == "Misc" })
        XCTAssertTrue(misc.hasNoBudget)
        XCTAssertEqual(misc.remaining, dec("-20"))
        XCTAssertTrue(misc.isOverBudget)
    }

    func testCategoryTypeIsCarried() throws {
        try category("Rent", budget: "1200", type: .fixed)
        XCTAssertEqual(report().categories.first?.typeName, "Fixed")
    }

    // MARK: - Uncategorized

    func testUncategorizedSpendingAppearsWhenPresent() throws {
        let groceries = try category("Groceries", budget: "300")
        try expense("50", "Fry's", on: 3, in: groceries)

        let temp = try category("Temp", budget: "0")
        try expense("43.72", "Orphan", on: 4, in: temp)
        try BudgetCategoryService.deleteCategory(temp, context: context)

        let uncategorized = try XCTUnwrap(report().uncategorized)
        XCTAssertEqual(uncategorized.spent, dec("43.72"))
        XCTAssertEqual(uncategorized.expenseCount, 1)
        XCTAssertEqual(report().summary.totalSpent, dec("93.72"),
                       "Uncategorized spending must still count toward the month")
    }

    func testNoUncategorizedRowWhenEverythingIsCategorised() throws {
        let groceries = try category("Groceries", budget: "300")
        try expense("50", "Fry's", on: 3, in: groceries)
        XCTAssertNil(report().uncategorized)
    }

    // MARK: - Ordering

    /// A report reads forward through the month, unlike the app's lists.
    func testExpensesAreOldestFirst() throws {
        let groceries = try category("Groceries", budget: "500")
        try expense("30", "Third", on: 20, in: groceries)
        try expense("10", "First", on: 3, in: groceries)
        try expense("20", "Second", on: 11, in: groceries)

        XCTAssertEqual(report().expenses.map(\.merchant), ["First", "Second", "Third"])
    }

    func testMoneyAddedIsOldestFirst() throws {
        try moneyAdded("500", "Family", on: 20)
        try moneyAdded("100", "Refund", on: 3)
        try moneyAdded("42.18", "Reimbursement", on: 11)

        XCTAssertEqual(report().moneyAdded.map(\.source),
                       ["Refund", "Reimbursement", "Family"])
    }

    /// Same-day records must always come out in the same order, or the same
    /// month would produce two different documents.
    func testSameDayOrderingIsStableAcrossBuilds() throws {
        let groceries = try category("Groceries", budget: "500")
        for index in 0..<6 {
            try expense("\(index + 1)", "Merchant\(index)", on: 8, in: groceries)
        }

        let first = report().expenses.map(\.id)
        let second = report().expenses.map(\.id)
        let third = MonthlyReportBuilder.makeReport(for: plan, context: context).expenses.map(\.id)

        XCTAssertEqual(first, second, "Two builds of the same month disagreed")
        XCTAssertEqual(first, third)
    }

    func testWeeklyReviewsAreOldestFirst() throws {
        try ReviewService.saveWeeklyReview(for: plan, weekStart: date(21),
                                           note: "Third week.", context: context)
        try ReviewService.saveWeeklyReview(for: plan, weekStart: date(7),
                                           note: "First week.", context: context)
        try ReviewService.saveWeeklyReview(for: plan, weekStart: date(14),
                                           note: "Second week.", context: context)

        XCTAssertEqual(report().weeklyReviews.map(\.note),
                       ["First week.", "Second week.", "Third week."])
    }

    // MARK: - Ledger detail

    func testExpenseRowsCarryEverythingTheReportNeeds() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        try expense("14.72", "Chipotle", on: 3, in: eatingOut, note: "Lunch after class")

        let row = try XCTUnwrap(report().expenses.first)
        XCTAssertEqual(row.merchant, "Chipotle")
        XCTAssertEqual(row.categoryName, "Eating Out")
        XCTAssertEqual(row.amount, dec("14.72"))
        XCTAssertEqual(row.note, "Lunch after class")
        XCTAssertEqual(row.date, date(3))
    }

    /// An expense whose category was deleted must still appear, named.
    func testUncategorizedExpenseIsLabelledNotOmitted() throws {
        let temp = try category("Temp", budget: "0")
        try expense("25", "Orphan", on: 4, in: temp)
        try BudgetCategoryService.deleteCategory(temp, context: context)

        let row = try XCTUnwrap(report().expenses.first)
        XCTAssertEqual(row.merchant, "Orphan")
        XCTAssertEqual(row.categoryName, "Uncategorized")
    }

    func testMoneyAddedRowsCarryTheirNotes() throws {
        try moneyAdded("100", "Refund", on: 5, note: "Returned headphones")
        let row = try XCTUnwrap(report().moneyAdded.first)
        XCTAssertEqual(row.source, "Refund")
        XCTAssertEqual(row.amount, dec("100"))
        XCTAssertEqual(row.note, "Returned headphones")
    }

    // MARK: - Reflection

    func testReflectionMapsOnlyAnsweredQuestions() throws {
        try ReviewService.saveMonthlyReview(
            for: plan,
            spentMoreThanExpected: "Yes, on eating out.",
            avoidablePurchase: nil,
            worthwhilePurchase: "The winter coat.",
            changeNextMonth: nil,
            additionalNotes: nil,
            context: context
        )

        let reflection = try XCTUnwrap(report().reflection)
        XCTAssertEqual(reflection.answers.count, 2, "Unanswered questions should not appear")
        XCTAssertEqual(reflection.answers.map(\.id),
                       ["spentMoreThanExpected", "worthwhilePurchase"])
        XCTAssertEqual(reflection.answers.first?.question,
                       "Did I spend more than I expected?")
        XCTAssertEqual(reflection.answers.first?.answer, "Yes, on eating out.")
    }

    func testNoReflectionWhenNoneWasWritten() throws {
        XCTAssertNil(report().reflection)
    }

    /// Opening a report must not create anything.
    func testBuildingAReportCreatesNoReflection() throws {
        _ = report()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyReview>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeeklyReview>()), 0)
    }

    // MARK: - Empty and awkward months

    func testAnEmptyMonthStillProducesAReport() throws {
        let snapshot = report()
        XCTAssertEqual(snapshot.summary.totalSpent, 0)
        XCTAssertEqual(snapshot.summary.safeToSpend, dec("1400"))
        XCTAssertTrue(snapshot.categories.isEmpty)
        XCTAssertTrue(snapshot.expenses.isEmpty)
        XCTAssertTrue(snapshot.moneyAdded.isEmpty)
        XCTAssertTrue(snapshot.weeklyReviews.isEmpty)
        XCTAssertNil(snapshot.uncategorized)
        XCTAssertNil(snapshot.reflection)
    }

    func testAMonthWithNoCategoriesStillReportsItsSpending() throws {
        let temp = try category("Temp", budget: "0")
        try expense("40", "Somewhere", on: 4, in: temp)
        try BudgetCategoryService.deleteCategory(temp, context: context)

        let snapshot = report()
        XCTAssertTrue(snapshot.categories.isEmpty)
        XCTAssertEqual(snapshot.expenses.count, 1)
        XCTAssertEqual(snapshot.summary.totalSpent, dec("40"))
        XCTAssertEqual(snapshot.uncategorized?.spent, dec("40"))
    }

    // MARK: - Decimal precision

    func testAwkwardDecimalsSurviveIntoTheReport() throws {
        let misc = try category("Misc", budget: "5000")
        let amounts = ["0.01", "0.10", "14.72", "42.18", "100.00"]
        for (index, amount) in amounts.enumerated() {
            try expense(amount, "M\(index)", on: index + 1, in: misc)
        }

        let rows = report().expenses
        for amount in amounts {
            XCTAssertTrue(rows.contains { $0.amount == dec(amount) },
                          "\(amount) did not reach the report exactly")
        }
        XCTAssertEqual(report().summary.totalSpent, dec("157.01"))
        XCTAssertEqual(report().categories.first?.remaining, dec("4842.99"))
    }

    // MARK: - Detail levels

    func testDetailLevelsDecideWhatIsIncluded() {
        XCTAssertFalse(ReportDetailLevel.summary.includesMoneyAdded)
        XCTAssertFalse(ReportDetailLevel.summary.includesReflection)
        XCTAssertFalse(ReportDetailLevel.summary.includesExpenseLedger)
        XCTAssertFalse(ReportDetailLevel.summary.includesWeeklyReviews)

        XCTAssertTrue(ReportDetailLevel.standard.includesMoneyAdded)
        XCTAssertTrue(ReportDetailLevel.standard.includesReflection)
        XCTAssertFalse(ReportDetailLevel.standard.includesExpenseLedger,
                       "Standard must not carry the whole ledger")
        XCTAssertFalse(ReportDetailLevel.standard.includesWeeklyReviews)

        XCTAssertTrue(ReportDetailLevel.full.includesMoneyAdded)
        XCTAssertTrue(ReportDetailLevel.full.includesReflection)
        XCTAssertTrue(ReportDetailLevel.full.includesExpenseLedger)
        XCTAssertTrue(ReportDetailLevel.full.includesWeeklyReviews)
    }

    // MARK: - Read-only

    /// Building a report must not touch a single record.
    func testBuildingAReportChangesNothing() throws {
        let eatingOut = try category("Eating Out", budget: "200")
        let expense = try expense("14.72", "Chipotle", on: 3, in: eatingOut)
        let entry = try moneyAdded("100", "Refund", on: 5)
        try ReviewService.saveWeeklyReview(for: plan, weekStart: date(7),
                                           note: "A note.", context: context)
        try ReviewService.saveMonthlyReview(
            for: plan, spentMoreThanExpected: "Yes.", avoidablePurchase: nil,
            worthwhilePurchase: nil, changeNextMonth: nil, additionalNotes: nil,
            context: context
        )

        let before = try counts()
        let expenseUpdatedBefore = expense.createdAt
        let entryUpdatedBefore = entry.createdAt

        _ = report()
        _ = MonthlyReportPDFRenderer.render(report: report(), level: .full)

        XCTAssertEqual(try counts(), before, "Reporting changed the number of records")
        XCTAssertEqual(expense.createdAt, expenseUpdatedBefore, "A timestamp moved")
        XCTAssertEqual(entry.createdAt, entryUpdatedBefore)
        XCTAssertFalse(plan.isClosed, "Reporting closed the month")
        XCTAssertEqual(plan.startingBalance, dec("2400"))
    }

    private func counts() throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<MonthlyPlan>()),
            try context.fetchCount(FetchDescriptor<BudgetCategory>()),
            try context.fetchCount(FetchDescriptor<Expense>()),
            try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()),
            try context.fetchCount(FetchDescriptor<WeeklyReview>()),
            try context.fetchCount(FetchDescriptor<MonthlyReview>())
        ]
    }
}
