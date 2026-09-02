import XCTest
import SwiftData
@testable import FinanceNotebook

/// Tests the store's own uniqueness constraint on `monthKey`, deliberately
/// bypassing `MonthlyPlanService` so that the service's guard cannot be what
/// makes these pass. This is the second layer: it is what protects the data if
/// some future code path forgets to go through the service.
final class SchemaUniquenessTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV1.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func insertDirectly(month: Int, year: Int, startingBalance: Decimal = 100) {
        context.insert(
            MonthlyPlan(
                month: month, year: year,
                startingBalance: startingBalance, protectedAmount: 0
            )
        )
    }

    private func planCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MonthlyPlan>())
    }

    /// Two September 2026 plans must not be able to coexist in the store.
    func testTwoPlansForTheSameMonthCannotBothPersist() throws {
        insertDirectly(month: 9, year: 2026, startingBalance: 2400)
        insertDirectly(month: 9, year: 2026, startingBalance: 999)

        // SwiftData resolves a unique-constraint collision by upserting rather
        // than throwing, so the assertion is on what ends up stored.
        try? context.save()

        XCTAssertEqual(try planCount(), 1,
                       "September 2026 persisted twice; monthKey uniqueness is not holding")

        let keys = try context.fetch(FetchDescriptor<MonthlyPlan>()).map(\.monthKey)
        XCTAssertEqual(keys, ["2026-09"])
    }

    func testSameMonthInDifferentYearsBothPersist() throws {
        insertDirectly(month: 9, year: 2026)
        insertDirectly(month: 9, year: 2027)
        try context.save()

        XCTAssertEqual(try planCount(), 2)
        let keys = try context.fetch(FetchDescriptor<MonthlyPlan>()).map(\.monthKey).sorted()
        XCTAssertEqual(keys, ["2026-09", "2027-09"])
    }

    func testDifferentMonthsInTheSameYearBothPersist() throws {
        insertDirectly(month: 9, year: 2026)
        insertDirectly(month: 10, year: 2026)
        try context.save()

        XCTAssertEqual(try planCount(), 2)
        let keys = try context.fetch(FetchDescriptor<MonthlyPlan>()).map(\.monthKey).sorted()
        XCTAssertEqual(keys, ["2026-09", "2026-10"])
    }

    func testAFullYearOfDistinctMonthsAllPersist() throws {
        for month in 1...12 {
            insertDirectly(month: month, year: 2026)
        }
        try context.save()
        XCTAssertEqual(try planCount(), 12)
    }

    /// The service must still reject duplicates itself, so the UI gets a real
    /// error rather than relying on the store to quietly absorb the collision.
    func testServiceStillRejectsDuplicatesBeforeReachingTheStore() throws {
        try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )

        XCTAssertThrowsError(
            try MonthlyPlanService.createPlan(
                month: 9, year: 2026, startingBalance: 1, protectedAmount: 0, context: context
            )
        ) { error in
            XCTAssertEqual(error as? MonthlyPlanError, .planAlreadyExists(month: 9, year: 2026))
        }

        XCTAssertEqual(try planCount(), 1)
    }
}
