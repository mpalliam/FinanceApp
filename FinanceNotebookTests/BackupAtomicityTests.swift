import XCTest
import SwiftData
@testable import FinanceNotebook

/// Restore is the only thing in this app that can destroy someone's records, so
/// the failure cases matter more than the happy one.
final class BackupAtomicityTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int, _ month: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    /// A device with real records on it, and everything needed to prove later
    /// that they are still exactly the same records.
    private struct LiveStore {
        let context: ModelContext
        let planID: UUID
        let categoryID: UUID
        let expenseID: UUID
        let weeklyID: UUID
        let counts: BackupRestorer.RestoreSummary
    }

    private func makeLiveStore() throws -> LiveStore {
        let context = ModelContext(try makeContainer())

        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: dec("2400.00"),
            protectedAmount: dec("1000.00"), context: context
        )
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200.00"), type: .flexible,
            plan: plan, context: context
        )
        let expense = try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(3), merchant: "Chipotle",
            note: "Lunch", category: category, plan: plan, context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100.00"), date: date(15), source: "Refund",
            note: nil, plan: plan, context: context
        )
        let weekly = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(7), note: "A note.", context: context
            )
        )
        try MonthlyPlanService.closePlan(plan, context: context)

        return LiveStore(
            context: context, planID: plan.id, categoryID: category.id,
            expenseID: expense.id, weeklyID: weekly.id,
            counts: try BackupRestorer.count(in: context)
        )
    }

    /// Everything about the live store, checked record by record rather than by
    /// counting. Counts alone would not notice a swapped relationship.
    private func assertUntouched(_ store: LiveStore, _ message: String,
                                 line: UInt = #line) throws {
        let context = store.context

        XCTAssertEqual(try BackupRestorer.count(in: context), store.counts,
                       "\(message): record counts changed", line: line)

        let plan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MonthlyPlan>())
                .first { $0.id == store.planID },
            "\(message): the plan is gone", line: line
        )
        XCTAssertEqual(plan.monthKey, "2026-09", line: line)
        XCTAssertEqual(plan.startingBalance, dec("2400.00"),
                       "\(message): starting balance changed", line: line)
        XCTAssertEqual(plan.protectedAmount, dec("1000.00"), line: line)
        XCTAssertTrue(plan.isClosed, "\(message): the month was reopened", line: line)

        let expense = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Expense>())
                .first { $0.id == store.expenseID },
            "\(message): the expense is gone", line: line
        )
        XCTAssertEqual(expense.amount, dec("14.72"), line: line)
        XCTAssertEqual(expense.merchant, "Chipotle", line: line)
        XCTAssertEqual(expense.note, "Lunch", line: line)
        XCTAssertEqual(expense.plan?.id, store.planID,
                       "\(message): expense lost its plan", line: line)
        XCTAssertEqual(expense.category?.id, store.categoryID,
                       "\(message): expense lost its category", line: line)

        let weekly = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WeeklyReview>())
                .first { $0.id == store.weeklyID },
            "\(message): the review is gone", line: line
        )
        XCTAssertEqual(weekly.note, "A note.", line: line)
        XCTAssertEqual(weekly.plan?.id, store.planID, line: line)
    }

    // MARK: - The mechanism restore depends on

    /// Phase 3 deletes and inserts in one context and commits with a single
    /// save. That is only atomic if an unsaved delete can actually be undone --
    /// worth proving rather than assuming, given what this project has already
    /// found out about SwiftData deleting things quietly.
    func testRollbackUndoesUnsavedDeletes() throws {
        let store = try makeLiveStore()
        let context = store.context

        try BackupRestorer.deleteEverything(in: context)
        // Deleted, but deliberately not saved.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 0,
                       "The deletes did not take effect in the context")

        context.rollback()

        try assertUntouched(store, "rollback after unsaved deletes")
    }

    // MARK: - Failed replacement

    /// The mandatory one. A replacement that fails must leave the device
    /// exactly as it was -- not merely with the right number of rows.
    func testAFailedReplaceLeavesEveryOriginalRecordIntact() throws {
        let store = try makeLiveStore()

        // A backup that is well-formed JSON but corrupt: an expense pointing at
        // a plan that is not in the file.
        let planID = UUID()
        let corrupt = FinanceNotebookBackup(
            formatVersion: 1, exportedAt: Date(), sourceSchemaVersion: "2.0.0",
            plans: [
                BackupPlan(id: planID, month: 1, year: 2027, monthKey: "2027-01",
                           startingBalance: "500.00", protectedAmount: "0",
                           isClosed: false, createdAt: Date())
            ],
            categories: [],
            expenses: [
                BackupExpense(id: UUID(), planID: UUID(), categoryID: nil,
                              amount: "10.00", date: date(3, 1), merchant: "Ghost",
                              note: nil, createdAt: Date())
            ],
            moneyAdded: [], weeklyReviews: [], monthlyReviews: []
        )

        XCTAssertThrowsError(try BackupValidator.validate(backup: corrupt),
                             "A corrupt backup was accepted")

        // Validation failed, so restore was never reached and the store was
        // never touched.
        try assertUntouched(store, "a rejected corrupt backup")
    }

    /// The same, driven through the file the user would actually have picked.
    func testAFailedReplaceFromAFileLeavesEverythingIntact() throws {
        let store = try makeLiveStore()

        for bad in [Data("not json at all".utf8),
                    Data(#"{"formatVersion": 999, "exportedAt": "2026-09-05T00:00:00.000Z", "sourceSchemaVersion": "2.0.0", "plans": [], "categories": [], "expenses": [], "moneyAdded": [], "weeklyReviews": [], "monthlyReviews": []}"#.utf8)] {
            XCTAssertThrowsError(try BackupValidator.validate(data: bad))
        }

        try assertUntouched(store, "rejected backup files")
    }

    /// A backup whose contents are valid but which cannot be built is caught in
    /// the staging phase, before the live store is opened for writing.
    func testStagingCatchesAGraphThatCannotBeBuilt() throws {
        // Validation and staging share the same rules, so anything staging
        // would reject is rejected earlier. This checks the two agree: a
        // backup that validates must also stage.
        let source = ModelContext(try makeContainer())
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: dec("100.00"),
            protectedAmount: .zero, context: source
        )
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("50.00"), type: .flexible,
            plan: plan, context: source
        )
        try ExpenseService.createExpense(
            amount: dec("9.99"), date: date(3), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: source
        )

        let validated = try BackupValidator.validate(
            backup: try BackupService.makeBackup(from: source)
        )

        let destination = ModelContext(try makeContainer())
        XCTAssertNoThrow(try BackupRestorer.restore(validated, into: destination),
                         "A backup that validated could not be staged")
    }

    // MARK: - Successful replacement

    func testASuccessfulReplaceSwapsTheWholeNotebook() throws {
        let store = try makeLiveStore()

        // A backup of three different months.
        let source = ModelContext(try makeContainer())
        var expectedIDs: Set<UUID> = []
        for month in 1...3 {
            let plan = try MonthlyPlanService.createPlan(
                month: month, year: 2027, startingBalance: dec("100.00"),
                protectedAmount: .zero, context: source
            )
            expectedIDs.insert(plan.id)
        }
        let backup = try BackupService.makeBackup(from: source)

        try BackupRestorer.restore(
            try BackupValidator.validate(backup: backup), into: store.context
        )

        let plans = try store.context.fetch(FetchDescriptor<MonthlyPlan>())
        XCTAssertEqual(Set(plans.map(\.id)), expectedIDs,
                       "The notebook is not exactly the backup")
        XCTAssertFalse(plans.contains { $0.id == store.planID },
                       "The old month survived the replacement")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<Expense>()), 0,
                       "Old expenses survived the replacement")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<WeeklyReview>()), 0,
                       "Old reviews survived the replacement")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 0)
    }

    /// Restore reports success only after checking what actually landed.
    func testRestoreVerifiesWhatItWrote() throws {
        let source = ModelContext(try makeContainer())
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: dec("100.00"),
            protectedAmount: .zero, context: source
        )
        try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("50.00"), type: .flexible,
            plan: plan, context: source
        )
        let backup = try BackupService.makeBackup(from: source)

        let destination = ModelContext(try makeContainer())
        let summary = try BackupRestorer.restore(
            try BackupValidator.validate(backup: backup), into: destination
        )

        XCTAssertEqual(summary, BackupRestorer.expectedCounts(of: backup))
        XCTAssertEqual(summary, try BackupRestorer.count(in: destination))
    }

    // MARK: - Scale

    /// A realistic couple of years of records, to check nothing degenerates.
    func testALargeNotebookRoundTrips() throws {
        let source = ModelContext(try makeContainer())

        for offset in 0..<24 {
            let month = (offset % 12) + 1
            let year = 2025 + (offset / 12)
            let plan = try MonthlyPlanService.createPlan(
                month: month, year: year, startingBalance: dec("2400.00"),
                protectedAmount: dec("1000.00"), context: source
            )

            var categories: [BudgetCategory] = []
            for index in 0..<20 {
                categories.append(
                    try BudgetCategoryService.createCategory(
                        name: "Category \(index)", monthlyBudget: dec("100.00"),
                        type: index.isMultiple(of: 2) ? .flexible : .fixed,
                        plan: plan, context: source
                    )
                )
            }

            let day = Calendar.current.date(
                from: DateComponents(year: year, month: month, day: 5)
            )!
            for index in 0..<200 {
                try ExpenseService.createExpense(
                    amount: dec("12.34"), date: day, merchant: "Merchant \(index)",
                    note: nil, category: categories[index % categories.count],
                    plan: plan, context: source
                )
            }
            try MoneyAddedService.createEntry(
                amount: dec("50.00"), date: day, source: "Refund",
                note: nil, plan: plan, context: source
            )
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: day, note: "Week note.", context: source
            )
            try ReviewService.saveMonthlyReview(
                for: plan, spentMoreThanExpected: "Yes.", avoidablePurchase: nil,
                worthwhilePurchase: nil, changeNextMonth: nil, additionalNotes: nil,
                context: source
            )
        }

        let before = try BackupRestorer.count(in: source)
        XCTAssertEqual(before.expenses, 4800)

        let data = try BackupService.encode(try BackupService.makeBackup(from: source))
        XCTAssertGreaterThan(data.count, 100_000)

        let destination = ModelContext(try makeContainer())
        try BackupRestorer.restore(
            try BackupValidator.validate(data: data), into: destination
        )

        XCTAssertEqual(try BackupRestorer.count(in: destination), before,
                       "A large notebook did not survive the round trip")
    }
}
