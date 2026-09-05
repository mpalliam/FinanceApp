import XCTest
import SwiftData
@testable import FinanceNotebook

final class BudgetCategoryServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var plan: MonthlyPlan!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: FinanceNotebookSchemaV1.self),
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026, startingBalance: 2400, protectedAmount: 1000, context: context
        )
    }

    override func tearDown() {
        plan = nil
        context = nil
        container = nil
    }

    func testCreatesCategoryOnTheGivenPlan() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: Decimal(string: "200.00")!,
            type: .flexible, plan: plan, context: context
        )

        XCTAssertEqual(category.name, "Eating Out")
        XCTAssertEqual(category.monthlyBudget, Decimal(string: "200.00")!)
        XCTAssertEqual(category.type, .flexible)
        XCTAssertEqual(category.plan?.id, plan.id)
        XCTAssertTrue(plan.categories.contains { $0.id == category.id })
    }

    func testTrimsName() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "  Eating Out  ", monthlyBudget: 0, type: .fixed, plan: plan, context: context
        )
        XCTAssertEqual(category.name, "Eating Out")
    }

    func testRejectsBlankName() throws {
        XCTAssertThrowsError(
            try BudgetCategoryService.createCategory(
                name: "", monthlyBudget: 100, type: .flexible, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError, .blankName) }
    }

    func testRejectsWhitespaceOnlyName() throws {
        XCTAssertThrowsError(
            try BudgetCategoryService.createCategory(
                name: "   \n ", monthlyBudget: 100, type: .flexible, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError, .blankName) }
    }

    func testRejectsNegativeBudget() throws {
        XCTAssertThrowsError(
            try BudgetCategoryService.createCategory(
                name: "Eating Out", monthlyBudget: Decimal(string: "-1")!,
                type: .flexible, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError, .negativeBudget) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 0)
    }

    /// A category can be tracked before a budget has been decided.
    func testAllowsZeroBudget() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Miscellaneous", monthlyBudget: 0, type: .flexible, plan: plan, context: context
        )
        XCTAssertEqual(category.monthlyBudget, 0)
    }
}
