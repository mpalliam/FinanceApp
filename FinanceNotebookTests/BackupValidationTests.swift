import XCTest
import SwiftData
@testable import FinanceNotebook

/// A bad backup must be refused before the database is touched.
///
/// Every test here checks two things: that the backup is rejected, and that a
/// store holding real data came through with every record intact. The second
/// half is the point -- rejecting corruption is only useful if rejecting it is
/// also harmless.
final class BackupValidationTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    /// A valid backup, to be corrupted in one specific way per test.
    private func makeValidBackup() -> FinanceNotebookBackup {
        let planID = UUID()
        let categoryID = UUID()
        return FinanceNotebookBackup(
            formatVersion: 1,
            exportedAt: Date(),
            sourceSchemaVersion: "2.0.0",
            plans: [
                BackupPlan(id: planID, month: 9, year: 2026, monthKey: "2026-09",
                           startingBalance: "2400.00", protectedAmount: "1000.00",
                           isClosed: false, createdAt: Date())
            ],
            categories: [
                BackupCategory(id: categoryID, planID: planID, name: "Eating Out",
                               monthlyBudget: "200.00", type: "flexible")
            ],
            expenses: [
                BackupExpense(id: UUID(), planID: planID, categoryID: categoryID,
                              amount: "14.72", date: date(3), merchant: "Chipotle",
                              note: nil, createdAt: Date())
            ],
            moneyAdded: [
                BackupMoneyAddedEntry(id: UUID(), planID: planID, amount: "100.00",
                                      date: date(15), source: "Refund",
                                      note: nil, createdAt: Date())
            ],
            weeklyReviews: [],
            monthlyReviews: []
        )
    }

    /// A store with real data in it, so every rejection can also be checked for
    /// having left that data alone.
    private func makeLiveStore() throws -> (ModelContext, BackupRestorer.RestoreSummary, UUID) {
        let context = ModelContext(try makeContainer())
        let plan = try MonthlyPlanService.createPlan(
            month: 5, year: 2026, startingBalance: dec("777.77"),
            protectedAmount: dec("100.00"), context: context
        )
        let category = try BudgetCategoryService.createCategory(
            name: "Groceries", monthlyBudget: dec("300.00"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("55.55"), date: Calendar.current.date(
                from: DateComponents(year: 2026, month: 5, day: 4))!,
            merchant: "Fry's", note: nil, category: category, plan: plan, context: context
        )
        try MonthlyPlanService.closePlan(plan, context: context)
        return (context, try BackupRestorer.count(in: context), plan.id)
    }

    /// Rejects the backup, and proves the live store is untouched afterwards.
    private func assertRejected(
        _ backup: FinanceNotebookBackup,
        _ expected: BackupError,
        _ message: String,
        line: UInt = #line
    ) throws {
        let (context, before, planID) = try makeLiveStore()

        XCTAssertThrowsError(try BackupValidator.validate(backup: backup), message,
                             line: line) { error in
            XCTAssertEqual(error as? BackupError, expected, message, line: line)
        }

        XCTAssertEqual(try BackupRestorer.count(in: context), before,
                       "\(message): the live store changed", line: line)
        let plan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MonthlyPlan>()).first, line: line
        )
        XCTAssertEqual(plan.id, planID, "\(message): the live plan lost its identity",
                       line: line)
        XCTAssertEqual(plan.startingBalance, dec("777.77"), line: line)
        XCTAssertTrue(plan.isClosed, "\(message): the live plan was reopened", line: line)
    }

    // MARK: - The valid case, so the corrupted ones mean something

    func testTheValidBackupPasses() throws {
        XCTAssertNoThrow(try BackupValidator.validate(backup: makeValidBackup()))
    }

    // MARK: - File level

    func testMalformedJSONIsRejected() throws {
        let (context, before, _) = try makeLiveStore()
        let garbage = Data("this is not a backup".utf8)

        XCTAssertThrowsError(try BackupValidator.validate(data: garbage)) {
            XCTAssertEqual($0 as? BackupError, .malformedBackup)
        }
        XCTAssertEqual(try BackupRestorer.count(in: context), before)
    }

    func testTruncatedJSONIsRejected() throws {
        let (context, before, _) = try makeLiveStore()
        let full = try BackupService.encode(makeValidBackup())
        let truncated = full.prefix(full.count / 2)

        XCTAssertThrowsError(try BackupValidator.validate(data: Data(truncated))) {
            XCTAssertEqual($0 as? BackupError, .malformedBackup)
        }
        XCTAssertEqual(try BackupRestorer.count(in: context), before)
    }

    func testWellFormedJSONOfTheWrongShapeIsRejected() throws {
        let (context, before, _) = try makeLiveStore()
        let wrong = Data(#"{"hello": "world"}"#.utf8)

        XCTAssertThrowsError(try BackupValidator.validate(data: wrong)) {
            XCTAssertEqual($0 as? BackupError, .malformedBackup)
        }
        XCTAssertEqual(try BackupRestorer.count(in: context), before)
    }

    /// A newer format may mean anything; guessing at it is worse than refusing.
    func testANewerFormatVersionIsRefusedRatherThanGuessedAt() throws {
        var backup = makeValidBackup()
        backup = FinanceNotebookBackup(
            formatVersion: 999, exportedAt: backup.exportedAt,
            sourceSchemaVersion: backup.sourceSchemaVersion,
            plans: backup.plans, categories: backup.categories,
            expenses: backup.expenses, moneyAdded: backup.moneyAdded,
            weeklyReviews: backup.weeklyReviews, monthlyReviews: backup.monthlyReviews
        )
        try assertRejected(backup, .unsupportedBackupVersion(found: 999, supported: 1),
                           "A newer backup format")
    }

    // MARK: - Months

    func testAnInvalidMonthIsRejected() throws {
        for month in [0, 13] {
            var backup = makeValidBackup()
            let plan = backup.plans[0]
            backup.plans = [BackupPlan(id: plan.id, month: month, year: 2026,
                                       monthKey: plan.monthKey,
                                       startingBalance: plan.startingBalance,
                                       protectedAmount: plan.protectedAmount,
                                       isClosed: false, createdAt: plan.createdAt)]
            try assertRejected(backup, .invalidMonth(month: month), "Month \(month)")
        }
    }

    /// A stored key that disagrees with its own month would give the app two
    /// answers to "which month is this".
    func testAMonthKeyThatDisagreesWithItsMonthIsRejected() throws {
        var backup = makeValidBackup()
        let plan = backup.plans[0]
        backup.plans = [BackupPlan(id: plan.id, month: 9, year: 2026,
                                   monthKey: "2026-10",
                                   startingBalance: plan.startingBalance,
                                   protectedAmount: plan.protectedAmount,
                                   isClosed: false, createdAt: plan.createdAt)]
        try assertRejected(backup,
                           .monthKeyMismatch(monthKey: "2026-10", expected: "2026-09"),
                           "A mismatched month key")
    }

    func testTwoPlansForTheSameMonthAreRejected() throws {
        var backup = makeValidBackup()
        let plan = backup.plans[0]
        backup.plans.append(
            BackupPlan(id: UUID(), month: 9, year: 2026, monthKey: "2026-09",
                       startingBalance: "1.00", protectedAmount: "0",
                       isClosed: false, createdAt: plan.createdAt)
        )
        try assertRejected(backup, .duplicateMonth(monthKey: "2026-09"),
                           "Two plans for one month")
    }

    // MARK: - Identity

    func testDuplicateIdentifiersAreRejected() throws {
        var backup = makeValidBackup()
        let expense = backup.expenses[0]
        backup.expenses.append(
            BackupExpense(id: expense.id, planID: expense.planID,
                          categoryID: expense.categoryID, amount: "9.99",
                          date: expense.date, merchant: "Duplicate",
                          note: nil, createdAt: expense.createdAt)
        )
        try assertRejected(backup, .duplicateIdentifier(id: expense.id),
                           "Two expenses with one id")
    }

    // MARK: - Relationships

    func testAnExpenseReferencingAMissingPlanIsRejected() throws {
        var backup = makeValidBackup()
        let stranger = UUID()
        let expense = backup.expenses[0]
        backup.expenses = [
            BackupExpense(id: expense.id, planID: stranger, categoryID: nil,
                          amount: expense.amount, date: expense.date,
                          merchant: expense.merchant, note: nil,
                          createdAt: expense.createdAt)
        ]
        try assertRejected(backup, .missingPlanReference(id: stranger),
                           "An expense with no plan")
    }

    func testAnExpenseReferencingAMissingCategoryIsRejected() throws {
        var backup = makeValidBackup()
        let stranger = UUID()
        let expense = backup.expenses[0]
        backup.expenses = [
            BackupExpense(id: expense.id, planID: expense.planID, categoryID: stranger,
                          amount: expense.amount, date: expense.date,
                          merchant: expense.merchant, note: nil,
                          createdAt: expense.createdAt)
        ]
        try assertRejected(backup, .missingCategoryReference(id: stranger),
                           "An expense with a missing category")
    }

    /// Restoring this as uncategorized would hide the corruption instead of
    /// reporting it.
    func testAnExpenseUsingAnotherMonthsCategoryIsRejected() throws {
        var backup = makeValidBackup()
        let septemberID = backup.plans[0].id
        let octoberID = UUID()
        let octoberCategoryID = UUID()

        backup.plans.append(
            BackupPlan(id: octoberID, month: 10, year: 2026, monthKey: "2026-10",
                       startingBalance: "100.00", protectedAmount: "0",
                       isClosed: false, createdAt: Date())
        )
        backup.categories.append(
            BackupCategory(id: octoberCategoryID, planID: octoberID,
                           name: "Groceries", monthlyBudget: "300.00", type: "flexible")
        )

        let expense = backup.expenses[0]
        backup.expenses = [
            BackupExpense(id: expense.id, planID: septemberID,
                          categoryID: octoberCategoryID, amount: expense.amount,
                          date: expense.date, merchant: expense.merchant,
                          note: nil, createdAt: expense.createdAt)
        ]
        try assertRejected(backup, .crossPlanCategory(expense: expense.id),
                           "An expense using another month's category")
    }

    // MARK: - Money

    func testAnUnparseableAmountIsRejected() throws {
        var backup = makeValidBackup()
        let expense = backup.expenses[0]
        backup.expenses = [
            BackupExpense(id: expense.id, planID: expense.planID,
                          categoryID: expense.categoryID, amount: "banana",
                          date: expense.date, merchant: expense.merchant,
                          note: nil, createdAt: expense.createdAt)
        ]
        try assertRejected(backup, .invalidDecimal(value: "banana"), "A non-numeric amount")
    }

    func testAZeroExpenseIsRejected() throws {
        var backup = makeValidBackup()
        let expense = backup.expenses[0]
        backup.expenses = [
            BackupExpense(id: expense.id, planID: expense.planID,
                          categoryID: expense.categoryID, amount: "0",
                          date: expense.date, merchant: expense.merchant,
                          note: nil, createdAt: expense.createdAt)
        ]
        try assertRejected(backup, .invalidAmount(value: "0"), "A zero expense")
    }

    func testNegativeMoneyAddedIsRejected() throws {
        var backup = makeValidBackup()
        let entry = backup.moneyAdded[0]
        backup.moneyAdded = [
            BackupMoneyAddedEntry(id: entry.id, planID: entry.planID, amount: "-10.00",
                                  date: entry.date, source: entry.source,
                                  note: nil, createdAt: entry.createdAt)
        ]
        try assertRejected(backup, .invalidAmount(value: "-10.00"), "Negative money added")
    }

    func testANegativeStartingBalanceIsRejected() throws {
        var backup = makeValidBackup()
        let plan = backup.plans[0]
        backup.plans = [BackupPlan(id: plan.id, month: 9, year: 2026,
                                   monthKey: "2026-09", startingBalance: "-1.00",
                                   protectedAmount: "0", isClosed: false,
                                   createdAt: plan.createdAt)]
        try assertRejected(backup, .negativeStartingBalance, "A negative starting balance")
    }

    func testANegativeProtectedAmountIsRejected() throws {
        var backup = makeValidBackup()
        let plan = backup.plans[0]
        backup.plans = [BackupPlan(id: plan.id, month: 9, year: 2026,
                                   monthKey: "2026-09", startingBalance: "100.00",
                                   protectedAmount: "-5.00", isClosed: false,
                                   createdAt: plan.createdAt)]
        try assertRejected(backup, .negativeProtectedAmount, "A negative protected amount")
    }

    // MARK: - Categories

    /// A type this version does not know cannot be guessed at without silently
    /// rewriting the user's budget.
    func testAnUnknownCategoryTypeIsRejected() throws {
        var backup = makeValidBackup()
        let category = backup.categories[0]
        backup.categories = [
            BackupCategory(id: category.id, planID: category.planID,
                           name: category.name, monthlyBudget: category.monthlyBudget,
                           type: "occasional")
        ]
        try assertRejected(backup, .invalidCategoryType(value: "occasional"),
                           "An unknown category type")
    }

    func testANegativeBudgetIsRejected() throws {
        var backup = makeValidBackup()
        let category = backup.categories[0]
        backup.categories = [
            BackupCategory(id: category.id, planID: category.planID,
                           name: category.name, monthlyBudget: "-1.00", type: "flexible")
        ]
        try assertRejected(backup, .negativeBudget, "A negative budget")
    }

    // MARK: - Reviews

    func testTwoReflectionsForOneMonthAreRejected() throws {
        var backup = makeValidBackup()
        let planID = backup.plans[0].id
        for _ in 0..<2 {
            backup.monthlyReviews.append(
                BackupMonthlyReview(id: UUID(), planID: planID,
                                    spentMoreThanExpected: "Yes.", avoidablePurchase: nil,
                                    worthwhilePurchase: nil, changeNextMonth: nil,
                                    additionalNotes: nil, createdAt: Date(), updatedAt: Date())
            )
        }
        try assertRejected(backup, .duplicateMonthlyReview(planID: planID),
                           "Two reflections for one month")
    }

    /// Two dates in one week are one week, so this is a duplicate even though
    /// the dates differ.
    func testTwoCheckInsForOneWeekAreRejected() throws {
        var backup = makeValidBackup()
        let planID = backup.plans[0].id
        let weekStart = ReviewService.weekStart(for: date(9))
        let laterInWeek = Calendar.current.date(byAdding: .day, value: 2, to: weekStart)!

        for start in [weekStart, laterInWeek] {
            backup.weeklyReviews.append(
                BackupWeeklyReview(id: UUID(), planID: planID, weekStartDate: start,
                                   note: "A note.", createdAt: Date(), updatedAt: Date())
            )
        }
        try assertRejected(backup, .duplicateWeeklyReview(planID: planID),
                           "Two check-ins in one week")
    }

    func testAReviewReferencingAMissingPlanIsRejected() throws {
        var backup = makeValidBackup()
        let stranger = UUID()
        backup.weeklyReviews = [
            BackupWeeklyReview(id: UUID(), planID: stranger, weekStartDate: date(7),
                               note: nil, createdAt: Date(), updatedAt: Date())
        ]
        try assertRejected(backup, .missingPlanReference(id: stranger),
                           "A review with no plan")
    }
}
