import XCTest
import SwiftData
@testable import FinanceNotebook

final class MoneyAddedServiceTests: XCTestCase {

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
        plan = nil
        context = nil
        container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @discardableResult
    private func addMoney(
        _ amount: String = "100", source: String = "Refund",
        note: String? = nil, on day: Int = 4
    ) throws -> MoneyAddedEntry {
        try MoneyAddedService.createEntry(
            amount: dec(amount), date: date(day), source: source,
            note: note, plan: plan, context: context
        )
    }

    private func entryCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MoneyAddedEntry>())
    }

    // MARK: - Creation

    func testCreatesValidEntry() throws {
        let entry = try addMoney()

        XCTAssertEqual(entry.amount, dec("100"))
        XCTAssertEqual(entry.source, "Refund")
        XCTAssertEqual(entry.plan?.monthKey, "2026-09")
        XCTAssertEqual(entry.date, date(4))
        XCTAssertNil(entry.note)
        XCTAssertEqual(try entryCount(), 1)
    }

    func testEntryIsReachableFromItsPlan() throws {
        let entry = try addMoney()
        XCTAssertTrue(plan.moneyAdded.contains { $0.id == entry.id })
    }

    func testSourceAndNoteAreTrimmed() throws {
        let entry = try addMoney(source: "  Refund  ", note: "  Amazon return  ")
        XCTAssertEqual(entry.source, "Refund")
        XCTAssertEqual(entry.note, "Amazon return")
    }

    func testWhitespaceOnlyNoteBecomesNil() throws {
        let entry = try addMoney(note: "   \n ")
        XCTAssertNil(entry.note)
    }

    // MARK: - Validation

    func testRejectsZeroAmount() throws {
        XCTAssertThrowsError(try addMoney("0")) {
            XCTAssertEqual($0 as? MoneyAddedError, .amountNotPositive)
        }
        XCTAssertEqual(try entryCount(), 0)
    }

    func testRejectsNegativeAmount() throws {
        XCTAssertThrowsError(try addMoney("-100")) {
            XCTAssertEqual($0 as? MoneyAddedError, .amountNotPositive)
        }
        XCTAssertEqual(try entryCount(), 0)
    }

    func testRejectsBlankSource() throws {
        XCTAssertThrowsError(try addMoney(source: "")) {
            XCTAssertEqual($0 as? MoneyAddedError, .blankSource)
        }
        XCTAssertEqual(try entryCount(), 0)
    }

    func testRejectsWhitespaceOnlySource() throws {
        XCTAssertThrowsError(try addMoney(source: "  \t \n ")) {
            XCTAssertEqual($0 as? MoneyAddedError, .blankSource)
        }
        XCTAssertEqual(try entryCount(), 0)
    }

    func testRejectsDateBeforeThePlansMonth() throws {
        XCTAssertThrowsError(
            try MoneyAddedService.createEntry(
                amount: dec("100"), date: date(20, 8, 2026), source: "Refund",
                note: nil, plan: plan, context: context
            )
        ) {
            XCTAssertEqual($0 as? MoneyAddedError,
                           .dateOutsidePlanMonth(monthTitle: plan.displayTitle))
        }
        XCTAssertEqual(try entryCount(), 0)
    }

    func testRejectsDateAfterThePlansMonth() throws {
        XCTAssertThrowsError(
            try MoneyAddedService.createEntry(
                amount: dec("100"), date: date(1, 10, 2026), source: "Refund",
                note: nil, plan: plan, context: context
            )
        ) {
            XCTAssertEqual($0 as? MoneyAddedError,
                           .dateOutsidePlanMonth(monthTitle: plan.displayTitle))
        }
    }

    func testRejectsDateInAnotherYear() throws {
        XCTAssertThrowsError(
            try MoneyAddedService.createEntry(
                amount: dec("100"), date: date(4, 9, 2025), source: "Refund",
                note: nil, plan: plan, context: context
            )
        ) {
            XCTAssertEqual($0 as? MoneyAddedError,
                           .dateOutsidePlanMonth(monthTitle: plan.displayTitle))
        }
    }

    func testValidEntryStillSucceedsAfterRejections() throws {
        XCTAssertThrowsError(try addMoney("0"))
        XCTAssertThrowsError(try addMoney(source: " "))
        let entry = try addMoney()
        XCTAssertEqual(entry.source, "Refund")
        XCTAssertEqual(try entryCount(), 1)
    }

    // MARK: - Decimal precision

    func testExactDecimalAmounts() throws {
        for value in ["0.01", "0.10", "42.18", "100.00"] {
            let entry = try addMoney(value, source: "S\(value)")
            XCTAssertEqual(entry.amount, dec(value), "\(value) was not stored exactly")
        }
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("142.29"))
    }

    func testManySmallEntriesSumExactly() throws {
        for index in 0..<10 {
            try addMoney("0.01", source: "Cashback\(index)")
        }
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("0.10"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2400.10"))
    }

    // MARK: - Editing

    func testEditingUpdatesInPlaceWithoutCreatingADuplicate() throws {
        let entry = try addMoney()
        let originalID = entry.id
        let originalCreatedAt = entry.createdAt

        try MoneyAddedService.updateEntry(
            entry,
            amount: dec("125.50"),
            date: entry.date,
            source: "Amazon Refund",
            note: "Returned headphones",
            context: context
        )

        XCTAssertEqual(try entryCount(), 1, "Editing created a second entry")
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<MoneyAddedEntry>()).first)
        XCTAssertEqual(stored.id, originalID, "The entry lost its identity")
        XCTAssertEqual(stored.createdAt, originalCreatedAt)
        XCTAssertEqual(stored.source, "Amazon Refund")
        XCTAssertEqual(stored.amount, dec("125.50"))
        XCTAssertEqual(stored.note, "Returned headphones")
    }

    func testEditingAppliesTheSameValidationRules() throws {
        let entry = try addMoney()

        XCTAssertThrowsError(
            try MoneyAddedService.updateEntry(
                entry, amount: 0, date: entry.date, source: "Refund",
                note: nil, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError, .amountNotPositive) }

        XCTAssertThrowsError(
            try MoneyAddedService.updateEntry(
                entry, amount: dec("5"), date: entry.date, source: "   ",
                note: nil, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError, .blankSource) }

        XCTAssertThrowsError(
            try MoneyAddedService.updateEntry(
                entry, amount: dec("5"), date: date(1, 10, 2026), source: "Refund",
                note: nil, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError,
                           .dateOutsidePlanMonth(monthTitle: plan.displayTitle)) }

        XCTAssertEqual(entry.amount, dec("100"),
                       "A rejected edit must not have changed the entry")
        XCTAssertEqual(entry.source, "Refund")
    }

    // MARK: - Deleting

    func testDeletingRemovesOnlyThatEntry() throws {
        let refund = try addMoney("100", source: "Refund")
        let family = try addMoney("500", source: "Family", on: 14)

        try MoneyAddedService.deleteEntry(refund, context: context)

        let remaining = try context.fetch(FetchDescriptor<MoneyAddedEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, family.id)
        XCTAssertEqual(remaining.first?.source, "Family")
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("500"))
    }

    func testDeletingLeavesThePlanAndItsExpensesIntact() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"),
            type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(2), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: context
        )
        let refund = try addMoney()

        try MoneyAddedService.deleteEntry(refund, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1,
                       "Deleting Money Added removed an expense")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 1)
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("14.72"))
    }

    // MARK: - Effect on the month's figures

    /// The full ledger, driven only through the services.
    func testSafeToSpendFollowsMoneyAddedThroughAddEditAndDelete() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("1000"),
            type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("600"), date: date(2), merchant: "Various",
            note: nil, category: category, plan: plan, context: context
        )

        // Starting 2400, spent 600, protected 1000, nothing added.
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), 0)
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2400"))
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("1800"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("800"))

        // --- Add 100 --------------------------------------------------------
        let refund = try addMoney("100")
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("100"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2500"))
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("1900"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("900"))

        // --- Edit to 150 ----------------------------------------------------
        try MoneyAddedService.updateEntry(
            refund, amount: dec("150"), date: refund.date,
            source: "Refund", note: nil, context: context
        )
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("150"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2550"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("950"))

        // --- Delete ---------------------------------------------------------
        try MoneyAddedService.deleteEntry(refund, context: context)
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), 0)
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2400"))
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: plan), dec("1800"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("800"))
    }

    /// Money Added is not negative spending: it must not touch totalSpent.
    func testMoneyAddedDoesNotReduceTotalSpent() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("500"),
            type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("120"), date: date(2), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: context
        )
        try addMoney("100")

        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("120"),
                       "Money Added was wrongly treated as negative spending")
        XCTAssertEqual(FinanceCalculator.spent(in: category), dec("120"))
    }

    func testMultipleEntriesAreSummed() throws {
        try addMoney("100", source: "Refund", on: 3)
        try addMoney("42.18", source: "Reimbursement", on: 8)
        try addMoney("500", source: "Family", on: 14)

        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("642.18"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("3042.18"))
    }

    // MARK: - Presentation

    func testSignedFormattingPutsThePlusOutsideTheSymbol() {
        let text = dec("100").signedCurrencyText
        XCTAssertTrue(text.hasPrefix("+"), "Expected a leading plus, got \"\(text)\"")
        XCTAssertFalse(text.contains("$+"), "Malformed signed currency: \"\(text)\"")
        XCTAssertTrue(text.contains("100"))
    }

    func testZeroIsNotSigned() {
        XCTAssertFalse(Decimal.zero.signedCurrencyText.contains("+"))
    }
}
