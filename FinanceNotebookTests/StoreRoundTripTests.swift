import XCTest
import SwiftData
@testable import FinanceNotebook

/// Writes a real store to disk, tears the container down completely, then
/// reopens the file through `FinanceNotebookMigrationPlan` and checks that
/// every record and relationship came back.
///
/// What this proves: the versioned schema and the migration plan can open an
/// existing on-disk store written by that schema, without losing data.
///
/// What this does NOT prove: that a V1 -> V2 migration preserves data. No V2
/// exists yet, so no cross-version migration can be executed. The first real
/// schema change must add its own migration test alongside its stage.
final class StoreRoundTripTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appending(path: "FinanceNotebook-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
        storeURL = nil
    }

    /// A fresh container pointed at the same file, always through the plan.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV2.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func seed(into context: ModelContext) throws {
        let plan = try MonthlyPlanService.createPlan(
            month: 9,
            year: 2026,
            startingBalance: Decimal(string: "2400.00")!,
            protectedAmount: Decimal(string: "1000.00")!,
            context: context
        )

        let category = BudgetCategory(
            name: "Eating Out",
            monthlyBudget: Decimal(string: "200.00")!,
            type: .flexible,
            plan: plan
        )
        context.insert(category)

        context.insert(
            Expense(
                amount: Decimal(string: "14.72")!,
                date: Date(),
                merchant: "Chipotle",
                category: category,
                plan: plan
            )
        )

        context.insert(
            MoneyAddedEntry(
                amount: Decimal(string: "100.00")!,
                date: Date(),
                source: "Refund",
                plan: plan
            )
        )

        try context.save()
    }

    func testSampleDataSurvivesAFullStoreReopen() throws {
        // --- Write, then drop every reference to the container ---------------
        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            try seed(into: context)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path),
                      "The store was never written to disk")

        // --- Reopen the same file through the migration plan -----------------
        let container = try makeContainer()
        let context = ModelContext(container)

        // MonthlyPlan
        let plans = try context.fetch(FetchDescriptor<MonthlyPlan>())
        XCTAssertEqual(plans.count, 1, "MonthlyPlan did not survive the reopen")
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.month, 9)
        XCTAssertEqual(plan.year, 2026)
        XCTAssertEqual(plan.monthKey, "2026-09")
        XCTAssertEqual(plan.startingBalance, Decimal(string: "2400.00")!,
                       "Starting balance changed across persistence")
        XCTAssertEqual(plan.protectedAmount, Decimal(string: "1000.00")!,
                       "Protected amount changed across persistence")

        // BudgetCategory
        let categories = try context.fetch(FetchDescriptor<BudgetCategory>())
        XCTAssertEqual(categories.count, 1, "BudgetCategory did not survive the reopen")
        let category = try XCTUnwrap(categories.first)
        XCTAssertEqual(category.name, "Eating Out")
        XCTAssertEqual(category.monthlyBudget, Decimal(string: "200.00")!)
        XCTAssertEqual(category.type, .flexible)

        // Expense, and both of its relationships
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 1, "Expense did not survive the reopen")
        let expense = try XCTUnwrap(expenses.first)
        XCTAssertEqual(expense.merchant, "Chipotle")
        XCTAssertEqual(expense.amount, Decimal(string: "14.72")!,
                       "Expense amount changed across persistence")
        XCTAssertEqual(expense.category?.id, category.id,
                       "Expense -> BudgetCategory relationship was lost")
        XCTAssertEqual(expense.plan?.id, plan.id,
                       "Expense -> MonthlyPlan relationship was lost")

        // MoneyAddedEntry
        let added = try context.fetch(FetchDescriptor<MoneyAddedEntry>())
        XCTAssertEqual(added.count, 1, "MoneyAddedEntry did not survive the reopen")
        let entry = try XCTUnwrap(added.first)
        XCTAssertEqual(entry.source, "Refund")
        XCTAssertEqual(entry.amount, Decimal(string: "100.00")!,
                       "Money added amount changed across persistence")
        XCTAssertEqual(entry.plan?.id, plan.id)

        // Reachable from the parent side too, not just by fetch
        XCTAssertEqual(plan.categories.count, 1)
        XCTAssertEqual(plan.expenses.count, 1)
        XCTAssertEqual(plan.moneyAdded.count, 1)
        XCTAssertEqual(category.expenses.count, 1)
    }

    /// Decimal must round-trip exactly. This is the check that would fail if
    /// monetary values were ever moved to Double.
    func testDecimalValuesRoundTripExactly() throws {
        let amounts = [
            Decimal(string: "14.72")!,
            Decimal(string: "0.01")!,
            Decimal(string: "2400.00")!,
            Decimal(string: "0.10")!,
            Decimal(string: "99999.99")!
        ]

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let plan = try MonthlyPlanService.createPlan(
                month: 1, year: 2026,
                startingBalance: Decimal(string: "2400.00")!,
                protectedAmount: .zero,
                context: context
            )
            for (index, amount) in amounts.enumerated() {
                context.insert(
                    Expense(amount: amount, date: Date(), merchant: "M\(index)", plan: plan)
                )
            }
            try context.save()
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let expenses = try context.fetch(FetchDescriptor<Expense>())
            .sorted { $0.merchant < $1.merchant }

        XCTAssertEqual(expenses.count, amounts.count)
        for (index, amount) in amounts.enumerated() {
            XCTAssertEqual(expenses[index].amount, amount,
                           "\(amount) did not survive persistence exactly")
        }

        // 0.01 + 0.02 == 0.03 exactly, which is the whole reason for Decimal.
        let penny = try XCTUnwrap(expenses.first { $0.amount == Decimal(string: "0.01")! })
        XCTAssertEqual(penny.amount + Decimal(string: "0.02")!, Decimal(string: "0.03")!)
    }

    /// Deleting a category must not delete spending history, even on disk.
    func testNullifyRuleHoldsAcrossAStoreReopen() throws {
        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            try seed(into: context)

            let category = try XCTUnwrap(
                try context.fetch(FetchDescriptor<BudgetCategory>()).first
            )
            context.delete(category)
            try context.save()
        }

        let container = try makeContainer()
        let context = ModelContext(container)

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 1, "Deleting a category destroyed an expense on disk")
        XCTAssertNil(expenses.first?.category)
        XCTAssertEqual(expenses.first?.merchant, "Chipotle")
        XCTAssertNotNil(expenses.first?.plan, "Expense lost its month")
    }
}
