import XCTest
import SwiftData
@testable import FinanceNotebook

/// Money Added create / edit / delete against a real on-disk store, with the
/// container fully released between each write and the check that follows it.
final class MoneyAddedPersistenceTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appending(path: "FinanceNotebook-money-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }
        storeURL = nil
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        )
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    /// September 2026 with a $100 Refund, then close the store.
    private func seedAndClose() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400"), protectedAmount: dec("1000"),
            context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100"), date: date(4), source: "Refund",
            note: nil, plan: plan, context: context
        )
    }

    func testEntrySurvivesAStoreReopen() throws {
        try seedAndClose()

        let container = try makeContainer()
        let context = ModelContext(container)

        let entries = try context.fetch(FetchDescriptor<MoneyAddedEntry>())
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.source, "Refund")
        XCTAssertEqual(entry.amount, dec("100"), "Amount changed across persistence")
        XCTAssertEqual(entry.date, date(4))
        XCTAssertEqual(entry.plan?.monthKey, "2026-09",
                       "MoneyAddedEntry -> MonthlyPlan did not survive")

        // Reachable from the parent side too, and still counted.
        let plan = try XCTUnwrap(entry.plan)
        XCTAssertEqual(plan.moneyAdded.count, 1)
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("100"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2500"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1500"))
    }

    func testEditsSurviveAStoreReopen() throws {
        try seedAndClose()

        var originalID: UUID!
        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<MoneyAddedEntry>()).first)
            originalID = entry.id

            try MoneyAddedService.updateEntry(
                entry,
                amount: dec("125.50"),
                date: entry.date,
                source: "Amazon Refund",
                note: "Returned headphones",
                context: context
            )
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<MoneyAddedEntry>())

        XCTAssertEqual(entries.count, 1, "Editing produced a duplicate on disk")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, originalID, "The edited entry lost its identity")
        XCTAssertEqual(entry.amount, dec("125.50"))
        XCTAssertEqual(entry.source, "Amazon Refund")
        XCTAssertEqual(entry.note, "Returned headphones")
    }

    func testDeletionSurvivesAStoreReopenAndLeavesThePlanIntact() throws {
        try seedAndClose()

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<MoneyAddedEntry>()).first)
            try MoneyAddedService.deleteEntry(entry, context: context)
        }

        let container = try makeContainer()
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 0,
                       "The deleted entry came back")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1,
                       "Deleting Money Added took the month with it")

        let plan = try XCTUnwrap(try context.fetch(FetchDescriptor<MonthlyPlan>()).first)
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), 0)
        XCTAssertEqual(FinanceCalculator.totalMoney(for: plan), dec("2400"))
    }

    func testExactDecimalAmountsRoundTrip() throws {
        let amounts = ["0.01", "0.10", "42.18", "100.00"]

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let plan = try MonthlyPlanService.createPlan(
                month: 9, year: 2026,
                startingBalance: dec("2400"), protectedAmount: .zero,
                context: context
            )
            for (index, value) in amounts.enumerated() {
                try MoneyAddedService.createEntry(
                    amount: dec(value), date: date(index + 1), source: "S\(index)",
                    note: nil, plan: plan, context: context
                )
            }
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<MoneyAddedEntry>())
            .sorted { $0.source < $1.source }

        XCTAssertEqual(entries.count, amounts.count)
        for (index, value) in amounts.enumerated() {
            XCTAssertEqual(entries[index].amount, dec(value),
                           "\(value) did not survive persistence exactly")
        }

        let plan = try XCTUnwrap(try context.fetch(FetchDescriptor<MonthlyPlan>()).first)
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: plan), dec("142.29"))
    }
}
