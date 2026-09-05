import XCTest
import SwiftData
@testable import FinanceNotebook

final class MonthKeyTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    // MARK: - Formatting

    func testCanonicalExamples() {
        XCTAssertEqual(MonthlyPlan.makeMonthKey(month: 1, year: 2026), "2026-01")
        XCTAssertEqual(MonthlyPlan.makeMonthKey(month: 9, year: 2026), "2026-09")
        XCTAssertEqual(MonthlyPlan.makeMonthKey(month: 12, year: 2026), "2026-12")
        XCTAssertEqual(MonthlyPlan.makeMonthKey(month: 12, year: 2027), "2027-12")
    }

    func testSingleDigitMonthsAreZeroPadded() {
        for month in 1...9 {
            XCTAssertEqual(
                MonthlyPlan.makeMonthKey(month: month, year: 2026),
                "2026-0\(month)",
                "month \(month) was not zero padded"
            )
        }
    }

    func testDoubleDigitMonthsAreNotPadded() {
        for month in 10...12 {
            XCTAssertEqual(MonthlyPlan.makeMonthKey(month: month, year: 2026), "2026-\(month)")
        }
    }

    func testEveryKeyIsExactlySevenCharacters() {
        for month in 1...12 {
            XCTAssertEqual(MonthlyPlan.makeMonthKey(month: month, year: 2026).count, 7)
        }
    }

    func testKeysSortChronologicallyAsStrings() {
        let keys = (1...12).map { MonthlyPlan.makeMonthKey(month: $0, year: 2026) }
        XCTAssertEqual(keys, keys.sorted(),
                       "Canonical keys should sort in calendar order as plain strings")
        XCTAssertLessThan(
            MonthlyPlan.makeMonthKey(month: 12, year: 2026),
            MonthlyPlan.makeMonthKey(month: 1, year: 2027)
        )
    }

    // MARK: - Generation on the model

    func testPlanCreatedThroughServiceCarriesTheDerivedKey() throws {
        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )
        XCTAssertEqual(plan.monthKey, "2026-09")
    }

    /// The key is derived in init, so it is correct even when a plan is built
    /// directly rather than through the service.
    func testKeyIsDerivedEvenWhenTheModelIsConstructedDirectly() {
        let plan = MonthlyPlan(month: 3, year: 2027, startingBalance: 0, protectedAmount: 0)
        XCTAssertEqual(plan.monthKey, "2027-03")
    }

    /// month, year and monthKey are all `private(set)`, so no caller outside
    /// MonthlyPlan.swift can put them out of step. This checks the invariant
    /// holds across every month of a year.
    func testKeyAlwaysAgreesWithMonthAndYear() throws {
        for month in 1...12 {
            let plan = try MonthlyPlanService.createPlan(
                month: month, year: 2026,
                startingBalance: 0, protectedAmount: 0, context: context
            )
            XCTAssertEqual(
                plan.monthKey,
                MonthlyPlan.makeMonthKey(month: plan.month, year: plan.year),
                "monthKey drifted from month/year for month \(month)"
            )
        }
    }

    func testKeySurvivesPersistence() throws {
        try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )
        let fetched = try context.fetch(FetchDescriptor<MonthlyPlan>())
        XCTAssertEqual(fetched.first?.monthKey, "2026-09")
    }
}
