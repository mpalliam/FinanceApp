import XCTest
import SwiftData
@testable import FinanceNotebook

/// Export, restore, and compare. The acceptance criterion for a backup is not
/// that it encodes -- it is that the notebook that comes back is the notebook
/// that went in.
final class BackupRoundTripTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// A notebook with every awkward case in it: two months, one closed, an
    /// uncategorized expense, awkward decimals, unicode, and reviews.
    @discardableResult
    private func seedRichNotebook(in context: ModelContext) throws -> [String: UUID] {
        var ids: [String: UUID] = [:]

        let september = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400.00"), protectedAmount: dec("1000.00"),
            context: context
        )
        ids["september"] = september.id

        let eatingOut = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200.00"),
            type: .flexible, plan: september, context: context
        )
        ids["eatingOut"] = eatingOut.id

        let rent = try BudgetCategoryService.createCategory(
            name: "Rent", monthlyBudget: dec("1200.00"),
            type: .fixed, plan: september, context: context
        )
        ids["rent"] = rent.id

        // Awkward decimals and awkward text.
        let chipotle = try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(3), merchant: "Chipotle",
            note: "Lunch with friends 🍜\nSecond line", category: eatingOut,
            plan: september, context: context
        )
        ids["chipotle"] = chipotle.id

        for amount in ["0.01", "0.10", "42.18", "100.00"] {
            try ExpenseService.createExpense(
                amount: dec(amount), date: date(5), merchant: "Precision \(amount)",
                note: nil, category: eatingOut, plan: september, context: context
            )
        }

        // An uncategorized expense, made the way they actually happen.
        let temp = try BudgetCategoryService.createCategory(
            name: "Temp", monthlyBudget: .zero, type: .flexible,
            plan: september, context: context
        )
        let orphan = try ExpenseService.createExpense(
            amount: dec("25.00"), date: date(7), merchant: "Orphan",
            note: nil, category: temp, plan: september, context: context
        )
        ids["orphan"] = orphan.id
        try BudgetCategoryService.deleteCategory(temp, context: context)

        let refund = try MoneyAddedService.createEntry(
            amount: dec("100.00"), date: date(15), source: "Refund",
            note: "Returned headphones", plan: september, context: context
        )
        ids["refund"] = refund.id

        let weekly = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: september, weekStart: date(7),
                note: "Cook at home more. ✍️", context: context
            )
        )
        ids["weekly"] = weekly.id

        let monthly = try XCTUnwrap(
            try ReviewService.saveMonthlyReview(
                for: september, spentMoreThanExpected: "A little.",
                avoidablePurchase: nil, worthwhilePurchase: "The winter coat.",
                changeNextMonth: "Plan meals.", additionalNotes: nil,
                context: context
            )
        )
        ids["monthly"] = monthly.id

        // A second month with different values, left closed.
        let october = try MonthlyPlanService.createNextPlan(
            from: september, startingBalance: dec("999999.99"),
            protectedAmount: dec("500.00"), copyCategories: true, context: context
        )
        ids["october"] = october.id
        try MonthlyPlanService.closePlan(september, context: context)

        return ids
    }

    // MARK: - The round trip

    func testARichNotebookSurvivesExportAndRestoreIntoAnEmptyStore() throws {
        let source = ModelContext(try makeContainer())
        let ids = try seedRichNotebook(in: source)

        let data = try BackupService.encode(try BackupService.makeBackup(from: source))

        // A completely separate, empty store.
        let destination = ModelContext(try makeContainer())
        XCTAssertFalse(BackupService.hasExistingData(in: destination))

        let validated = try BackupValidator.validate(data: data)
        try BackupRestorer.restore(validated, into: destination)

        // --- Counts ----------------------------------------------------------
        XCTAssertEqual(try BackupRestorer.count(in: destination),
                       try BackupRestorer.count(in: source),
                       "The restored notebook is a different size")

        // --- Identity: every id survives -------------------------------------
        let plans = try destination.fetch(FetchDescriptor<MonthlyPlan>())
        let september = try XCTUnwrap(plans.first { $0.id == ids["september"] },
                                      "The plan lost its identity")
        let october = try XCTUnwrap(plans.first { $0.id == ids["october"] })

        XCTAssertEqual(september.monthKey, "2026-09")
        XCTAssertEqual(september.startingBalance, dec("2400.00"))
        XCTAssertEqual(september.protectedAmount, dec("1000.00"))
        XCTAssertTrue(september.isClosed, "A closed month came back open")

        XCTAssertEqual(october.startingBalance, dec("999999.99"),
                       "A large decimal did not survive")
        XCTAssertFalse(october.isClosed)

        // --- Relationships ------------------------------------------------------
        let expenses = try destination.fetch(FetchDescriptor<Expense>())
        let chipotle = try XCTUnwrap(expenses.first { $0.id == ids["chipotle"] },
                                     "The expense lost its identity")
        XCTAssertEqual(chipotle.plan?.id, ids["september"],
                       "Expense -> plan did not survive")
        XCTAssertEqual(chipotle.category?.id, ids["eatingOut"],
                       "Expense -> category did not survive")
        XCTAssertEqual(chipotle.amount, dec("14.72"))
        XCTAssertEqual(chipotle.note, "Lunch with friends 🍜\nSecond line",
                       "Unicode or newlines did not survive")

        let orphan = try XCTUnwrap(expenses.first { $0.id == ids["orphan"] })
        XCTAssertNil(orphan.category, "An uncategorized expense gained a category")
        XCTAssertEqual(orphan.plan?.id, ids["september"])

        let refund = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<MoneyAddedEntry>())
                .first { $0.id == ids["refund"] }
        )
        XCTAssertEqual(refund.plan?.id, ids["september"])
        XCTAssertEqual(refund.amount, dec("100.00"))
        XCTAssertEqual(refund.note, "Returned headphones")

        // --- Reviews --------------------------------------------------------------
        let weekly = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<WeeklyReview>())
                .first { $0.id == ids["weekly"] }
        )
        XCTAssertEqual(weekly.plan?.id, ids["september"])
        XCTAssertEqual(weekly.note, "Cook at home more. ✍️")

        let monthly = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<MonthlyReview>())
                .first { $0.id == ids["monthly"] }
        )
        XCTAssertEqual(monthly.plan?.id, ids["september"])
        XCTAssertEqual(monthly.worthwhilePurchase, "The winter coat.")
        XCTAssertNil(monthly.avoidablePurchase, "An unanswered question gained an answer")

        // --- Categories -------------------------------------------------------------
        let categories = try destination.fetch(FetchDescriptor<BudgetCategory>())
        let rent = try XCTUnwrap(categories.first { $0.id == ids["rent"] })
        XCTAssertEqual(rent.type, .fixed, "The category type did not survive")
        XCTAssertEqual(rent.monthlyBudget, dec("1200.00"))
        XCTAssertEqual(rent.plan?.id, ids["september"])

        // --- And the totals still come out the same ------------------------------
        XCTAssertEqual(FinanceCalculator.summary(for: september),
                       FinanceCalculator.summary(
                           for: try XCTUnwrap(
                               try source.fetch(FetchDescriptor<MonthlyPlan>())
                                   .first { $0.id == ids["september"] })),
                       "The restored month does not add up the same way")
    }

    /// Every awkward decimal, through SwiftData, JSON, and back.
    func testExactDecimalsSurviveTheWholeRoundTrip() throws {
        let source = ModelContext(try makeContainer())
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: dec("2400.00"),
            protectedAmount: dec("999999.99"), context: source
        )
        let category = try BudgetCategoryService.createCategory(
            name: "Misc", monthlyBudget: dec("0.01"), type: .flexible,
            plan: plan, context: source
        )
        let amounts = ["0.01", "0.10", "14.72", "42.18", "100.00", "2400.00", "999999.99"]
        for (index, amount) in amounts.enumerated() {
            try ExpenseService.createExpense(
                amount: dec(amount), date: date(index + 1), merchant: "M\(index)",
                note: nil, category: category, plan: plan, context: source
            )
        }

        let data = try BackupService.encode(try BackupService.makeBackup(from: source))

        // The file itself must contain strings, not JSON numbers.
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"0.01\""), "Money was not written as a string")
        XCTAssertTrue(json.contains("\"999999.99\""))
        XCTAssertFalse(json.contains(": 14.72"), "Money was written as a JSON number")

        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(try BackupValidator.validate(data: data), into: destination)

        let restored = try destination.fetch(FetchDescriptor<Expense>())
        for amount in amounts {
            XCTAssertTrue(restored.contains { $0.amount == dec(amount) },
                          "\(amount) did not survive the round trip exactly")
        }
        let restoredPlan = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<MonthlyPlan>()).first
        )
        XCTAssertEqual(restoredPlan.protectedAmount, dec("999999.99"))
        XCTAssertEqual(
            try XCTUnwrap(try destination.fetch(FetchDescriptor<BudgetCategory>()).first)
                .monthlyBudget,
            dec("0.01")
        )
    }

    /// Dates survive to the documented millisecond precision.
    func testDatesSurviveToTheDocumentedPrecision() throws {
        let source = ModelContext(try makeContainer())
        let ids = try seedRichNotebook(in: source)

        let originalExpense = try XCTUnwrap(
            try source.fetch(FetchDescriptor<Expense>()).first { $0.id == ids["chipotle"] }
        )
        let originalWeekly = try XCTUnwrap(
            try source.fetch(FetchDescriptor<WeeklyReview>()).first { $0.id == ids["weekly"] }
        )

        let data = try BackupService.encode(try BackupService.makeBackup(from: source))
        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(try BackupValidator.validate(data: data), into: destination)

        let restoredExpense = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<Expense>()).first { $0.id == ids["chipotle"] }
        )
        let restoredWeekly = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<WeeklyReview>())
                .first { $0.id == ids["weekly"] }
        )

        let tolerance = BackupCoding.datePrecision
        XCTAssertEqual(restoredExpense.date.timeIntervalSinceReferenceDate,
                       originalExpense.date.timeIntervalSinceReferenceDate,
                       accuracy: tolerance, "Expense date drifted")
        XCTAssertEqual(restoredExpense.createdAt.timeIntervalSinceReferenceDate,
                       originalExpense.createdAt.timeIntervalSinceReferenceDate,
                       accuracy: tolerance, "createdAt drifted")
        XCTAssertEqual(restoredWeekly.weekStartDate.timeIntervalSinceReferenceDate,
                       originalWeekly.weekStartDate.timeIntervalSinceReferenceDate,
                       accuracy: tolerance, "weekStartDate drifted")
        XCTAssertEqual(restoredWeekly.updatedAt.timeIntervalSinceReferenceDate,
                       originalWeekly.updatedAt.timeIntervalSinceReferenceDate,
                       accuracy: tolerance, "updatedAt drifted")
    }

    /// A restored closed month must still refuse financial writes and still
    /// accept reviews.
    func testRestoredClosedMonthKeepsItsBehaviour() throws {
        let source = ModelContext(try makeContainer())
        let ids = try seedRichNotebook(in: source)

        let data = try BackupService.encode(try BackupService.makeBackup(from: source))
        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(try BackupValidator.validate(data: data), into: destination)

        let september = try XCTUnwrap(
            try destination.fetch(FetchDescriptor<MonthlyPlan>())
                .first { $0.id == ids["september"] }
        )
        XCTAssertTrue(september.isClosed)

        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: dec("10"), date: date(9), merchant: "Nope", note: nil,
                category: september.categories.first, plan: september, context: destination
            )
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: september.displayTitle)) }

        // Reviews are commentary, and stay writable.
        XCTAssertNoThrow(
            try ReviewService.saveMonthlyReview(
                for: september, spentMoreThanExpected: "Still thinking.",
                avoidablePurchase: nil, worthwhilePurchase: nil,
                changeNextMonth: nil, additionalNotes: nil, context: destination
            )
        )
    }

    /// Export must not touch anything.
    func testExportingChangesNothing() throws {
        let context = ModelContext(try makeContainer())
        let ids = try seedRichNotebook(in: context)

        let before = try BackupRestorer.count(in: context)
        let expense = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Expense>()).first { $0.id == ids["chipotle"] }
        )
        let createdBefore = expense.createdAt
        let plan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MonthlyPlan>())
                .first { $0.id == ids["september"] }
        )
        let closedBefore = plan.isClosed

        _ = try BackupService.encode(try BackupService.makeBackup(from: context))

        XCTAssertEqual(try BackupRestorer.count(in: context), before,
                       "Exporting changed the number of records")
        XCTAssertEqual(expense.createdAt, createdBefore, "Exporting moved a timestamp")
        XCTAssertEqual(plan.isClosed, closedBefore, "Exporting changed a closed flag")
    }

    /// Two exports of an unchanged notebook must produce the same bytes.
    func testExportIsDeterministic() throws {
        let context = ModelContext(try makeContainer())
        try seedRichNotebook(in: context)

        let stamp = Date()
        let first = try BackupService.encode(
            try BackupService.makeBackup(from: context, exportedAt: stamp)
        )
        let second = try BackupService.encode(
            try BackupService.makeBackup(from: context, exportedAt: stamp)
        )
        XCTAssertEqual(first, second, "Two exports of the same notebook differ")
    }

    /// Restore, export again, and the second file should describe the same
    /// notebook as the first.
    func testExportingRestoredDataProducesTheSameNotebook() throws {
        let source = ModelContext(try makeContainer())
        try seedRichNotebook(in: source)

        let stamp = Date()
        let backupA = try BackupService.makeBackup(from: source, exportedAt: stamp)

        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(
            try BackupValidator.validate(backup: backupA), into: destination
        )
        let backupB = try BackupService.makeBackup(from: destination, exportedAt: stamp)

        // exportedAt is pinned so only the contents can differ.
        XCTAssertEqual(backupA, backupB, "A round trip changed the notebook")
    }

    // MARK: - Empty

    func testAnEmptyNotebookExportsAndRestores() throws {
        let source = ModelContext(try makeContainer())
        let data = try BackupService.encode(try BackupService.makeBackup(from: source))

        let validated = try BackupValidator.validate(data: data)
        XCTAssertTrue(validated.preview.isEmpty)
        XCTAssertEqual(validated.preview.planCount, 0)

        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(validated, into: destination)
        XCTAssertEqual(try BackupRestorer.count(in: destination).plans, 0)
    }

    /// Replacing real data with an empty backup is allowed, and empties it.
    func testRestoringAnEmptyBackupOverExistingDataClearsIt() throws {
        let empty = ModelContext(try makeContainer())
        let emptyBackup = try BackupService.makeBackup(from: empty)

        let context = ModelContext(try makeContainer())
        try seedRichNotebook(in: context)
        XCTAssertTrue(BackupService.hasExistingData(in: context))

        try BackupRestorer.restore(
            try BackupValidator.validate(backup: emptyBackup), into: context
        )

        XCTAssertEqual(try BackupRestorer.count(in: context),
                       BackupRestorer.RestoreSummary(plans: 0, categories: 0, expenses: 0,
                                                     moneyAdded: 0, weeklyReviews: 0,
                                                     monthlyReviews: 0))
        XCTAssertFalse(BackupService.hasExistingData(in: context))
    }

    // MARK: - Repeats and replacement

    /// Restoring the same backup twice must not duplicate anything.
    func testRestoringTheSameBackupTwiceIsIdempotent() throws {
        let source = ModelContext(try makeContainer())
        try seedRichNotebook(in: source)
        let backup = try BackupService.makeBackup(from: source)
        let validated = try BackupValidator.validate(backup: backup)

        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(validated, into: destination)
        let afterFirst = try BackupRestorer.count(in: destination)

        try BackupRestorer.restore(validated, into: destination)
        let afterSecond = try BackupRestorer.count(in: destination)

        XCTAssertEqual(afterFirst, afterSecond, "Restoring twice duplicated records")
        XCTAssertEqual(afterSecond, BackupRestorer.expectedCounts(of: backup))
    }

    /// Replacing must leave nothing of the old notebook behind.
    func testReplaceLeavesNoTraceOfTheOldNotebook() throws {
        // The backup: three months at the start of the year.
        let source = ModelContext(try makeContainer())
        var backupPlanIDs: Set<UUID> = []
        for month in 1...3 {
            let plan = try MonthlyPlanService.createPlan(
                month: month, year: 2027, startingBalance: dec("100.00"),
                protectedAmount: .zero, context: source
            )
            backupPlanIDs.insert(plan.id)
        }
        let backup = try BackupService.makeBackup(from: source)

        // The device: September, with real records in it.
        let device = ModelContext(try makeContainer())
        let ids = try seedRichNotebook(in: device)

        try BackupRestorer.restore(
            try BackupValidator.validate(backup: backup), into: device
        )

        let plans = try device.fetch(FetchDescriptor<MonthlyPlan>())
        XCTAssertEqual(Set(plans.map(\.id)), backupPlanIDs,
                       "The replaced notebook is not exactly the backup")
        XCTAssertFalse(plans.contains { $0.id == ids["september"] },
                       "The old September survived a replacement")
        XCTAssertEqual(try device.fetchCount(FetchDescriptor<Expense>()), 0,
                       "Old expenses survived a replacement")
        XCTAssertEqual(try device.fetchCount(FetchDescriptor<WeeklyReview>()), 0,
                       "Old reviews survived a replacement")
    }
}
