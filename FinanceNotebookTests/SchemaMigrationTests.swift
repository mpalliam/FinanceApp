import XCTest
import SwiftData
import SQLite3
@testable import FinanceNotebook

/// The real thing: a store written by V1, reopened through the migration plan
/// as V2, with every original record checked.
///
/// This is a genuine on-disk migration, not a model comparison. It is possible
/// because FinanceNotebookSchemaV1 still lists exactly the four finance models
/// and nothing else, so a container opened with it writes a true V1 store.
final class SchemaMigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appending(path: "FinanceNotebook-migration-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }
        storeURL = nil
    }

    func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// A container speaking V1 only. No migration plan: this is what the app
    /// looked like before this milestone.
    func makeV1Container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV1.self)
        return try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        )
    }

    /// A container speaking V2, through the migration plan. This is the app as
    /// it now ships.
    func makeV2Container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: FinanceNotebookMigrationPlan.self,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        )
    }

    /// Identifiers captured from the V1 store so the same objects can be
    /// recognised after migration rather than merely counted.
    struct Fixture {
        var septemberID: UUID!
        var octoberID: UUID!
        var eatingOutID: UUID!
        var chipotleID: UUID!
        var orphanID: UUID!
        var refundID: UUID!
    }

    /// Writes a V1 store containing everything that must survive: two months,
    /// one of them closed, categories, expenses including an uncategorized one,
    /// money added, and awkward Decimal values.
    ///
    /// Built from the V1 *nested* model types, not the app's live ones, so this
    /// is genuinely a store as Milestone 5 would have written it.
    @discardableResult
    func writeV1Store() throws -> Fixture {
        typealias V1 = FinanceNotebookSchemaV1
        var fixture = Fixture()

        let container = try makeV1Container()
        let context = ModelContext(container)

        let september = V1.MonthlyPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400.00"), protectedAmount: dec("1000.00")
        )
        context.insert(september)
        fixture.septemberID = september.id

        let eatingOut = V1.BudgetCategory(
            name: "Eating Out", monthlyBudget: dec("200.00"),
            type: .flexible, plan: september
        )
        context.insert(eatingOut)
        fixture.eatingOutID = eatingOut.id

        let chipotle = V1.Expense(
            amount: dec("14.72"), date: date(4), merchant: "Chipotle",
            note: "Dinner after class", category: eatingOut, plan: september
        )
        context.insert(chipotle)
        fixture.chipotleID = chipotle.id

        // Awkward decimals, to prove nothing goes through Double.
        for (index, amount) in ["0.01", "42.18", "100.00"].enumerated() {
            context.insert(
                V1.Expense(
                    amount: dec(amount), date: date(index + 5),
                    merchant: "Precision\(index)", category: eatingOut, plan: september
                )
            )
        }

        // An uncategorized expense, made the way they actually occur: its
        // category is deleted and the nullify rule leaves the expense behind.
        let temp = V1.BudgetCategory(
            name: "Temp", monthlyBudget: .zero, type: .flexible, plan: september
        )
        context.insert(temp)
        let orphan = V1.Expense(
            amount: dec("25.00"), date: date(7), merchant: "Orphan",
            category: temp, plan: september
        )
        context.insert(orphan)
        fixture.orphanID = orphan.id
        try context.save()
        context.delete(temp)

        let refund = V1.MoneyAddedEntry(
            amount: dec("100.00"), date: date(15), source: "Refund", plan: september
        )
        context.insert(refund)
        fixture.refundID = refund.id

        // A second month, left open, so both states are exercised.
        let october = V1.MonthlyPlan(
            month: 10, year: 2026,
            startingBalance: dec("1876.00"), protectedAmount: dec("1000.00")
        )
        context.insert(october)
        context.insert(
            V1.BudgetCategory(
                name: "Eating Out", monthlyBudget: dec("200.00"),
                type: .flexible, plan: october
            )
        )
        fixture.octoberID = october.id

        // September is closed. This flag must survive.
        september.isClosed = true

        try context.save()
        return fixture
    }

    // MARK: - The store really is V1 before migrating

    func testTheStoreWrittenByV1HasNoReviewTables() throws {
        try writeV1Store()

        let tables = try Self.tableNames(in: storeURL)
        XCTAssertTrue(tables.contains("ZMONTHLYPLAN"))
        XCTAssertTrue(tables.contains("ZEXPENSE"))
        XCTAssertFalse(tables.contains("ZWEEKLYREVIEW"),
                       "The V1 store already had review tables; it is not a real V1 store")
        XCTAssertFalse(tables.contains("ZMONTHLYREVIEW"),
                       "The V1 store already had review tables; it is not a real V1 store")
    }

    /// V1's models had to become nested copies so that V2's review
    /// relationship could not reach back into them. That is only safe if the
    /// nested copies still describe the *same* schema -- if nesting changed an
    /// entity or column name, every existing store would be orphaned.
    ///
    /// These column lists were read out of the real store this app was carrying
    /// at the end of Milestone 5, before any of this milestone's changes.
    func testTheNestedV1ModelsProduceTheOriginalStoreStructure() throws {
        try writeV1Store()

        let expected: [String: Set<String>] = [
            "ZMONTHLYPLAN": ["Z_PK", "Z_ENT", "Z_OPT", "ZISCLOSED", "ZMONTH", "ZYEAR",
                             "ZCREATEDAT", "ZPROTECTEDAMOUNT", "ZSTARTINGBALANCE",
                             "ZMONTHKEY", "ZID"],
            "ZBUDGETCATEGORY": ["Z_PK", "Z_ENT", "Z_OPT", "ZPLAN", "ZMONTHLYBUDGET",
                                "ZNAME", "ZTYPE", "ZID"],
            "ZEXPENSE": ["Z_PK", "Z_ENT", "Z_OPT", "ZCATEGORY", "ZPLAN", "ZCREATEDAT",
                         "ZDATE", "ZAMOUNT", "ZMERCHANT", "ZNOTE", "ZID"],
            "ZMONEYADDEDENTRY": ["Z_PK", "Z_ENT", "Z_OPT", "ZPLAN", "ZCREATEDAT",
                                 "ZDATE", "ZAMOUNT", "ZNOTE", "ZSOURCE", "ZID"]
        ]

        for (table, columns) in expected {
            XCTAssertEqual(
                try Self.columnNames(of: table, in: storeURL), columns,
                "\(table) no longer matches the Milestone 5 store; nesting V1 changed the schema"
            )
        }
    }

    // MARK: - The migration itself

    func testEveryV1RecordSurvivesMigrationToV2() throws {
        let fixture = try writeV1Store()

        // Reopen the very same file as V2.
        let container = try makeV2Container()
        let context = ModelContext(container)

        // --- Plans ----------------------------------------------------------
        let plans = try context.fetch(FetchDescriptor<MonthlyPlan>())
        XCTAssertEqual(plans.count, 2, "A month was lost in migration")

        let september = try XCTUnwrap(plans.first { $0.id == fixture.septemberID },
                                      "September lost its identity")
        let october = try XCTUnwrap(plans.first { $0.id == fixture.octoberID },
                                    "October lost its identity")

        XCTAssertEqual(september.month, 9)
        XCTAssertEqual(september.year, 2026)
        XCTAssertEqual(september.monthKey, "2026-09")
        XCTAssertEqual(september.startingBalance, dec("2400.00"))
        XCTAssertEqual(september.protectedAmount, dec("1000.00"))
        XCTAssertTrue(september.isClosed, "A closed month came back open")

        XCTAssertEqual(october.monthKey, "2026-10")
        XCTAssertEqual(october.startingBalance, dec("1876.00"))
        XCTAssertFalse(october.isClosed, "An open month came back closed")

        // --- Categories -----------------------------------------------------
        let categories = try context.fetch(FetchDescriptor<BudgetCategory>())
        // Eating Out in September, plus the copy in October. Temp was deleted.
        XCTAssertEqual(categories.count, 2)
        let eatingOut = try XCTUnwrap(categories.first { $0.id == fixture.eatingOutID },
                                      "The category lost its identity")
        XCTAssertEqual(eatingOut.name, "Eating Out")
        XCTAssertEqual(eatingOut.monthlyBudget, dec("200.00"))
        XCTAssertEqual(eatingOut.type, .flexible)
        XCTAssertEqual(eatingOut.plan?.id, september.id,
                       "Category -> MonthlyPlan did not survive")

        // --- Expenses and both of their relationships -----------------------
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 5, "An expense was lost in migration")

        let chipotle = try XCTUnwrap(expenses.first { $0.id == fixture.chipotleID },
                                     "The expense lost its identity")
        XCTAssertEqual(chipotle.merchant, "Chipotle")
        XCTAssertEqual(chipotle.amount, dec("14.72"))
        XCTAssertEqual(chipotle.note, "Dinner after class")
        XCTAssertEqual(chipotle.category?.id, eatingOut.id,
                       "Expense -> BudgetCategory did not survive")
        XCTAssertEqual(chipotle.plan?.id, september.id,
                       "Expense -> MonthlyPlan did not survive")

        // --- The uncategorized expense stays uncategorized -------------------
        let orphan = try XCTUnwrap(expenses.first { $0.id == fixture.orphanID })
        XCTAssertNil(orphan.category, "The uncategorized expense gained a category")
        XCTAssertEqual(orphan.plan?.id, september.id, "The orphan lost its month")
        XCTAssertEqual(orphan.amount, dec("25.00"))

        // --- Decimal precision ------------------------------------------------
        for value in ["0.01", "42.18", "100.00", "14.72", "25.00"] {
            XCTAssertTrue(expenses.contains { $0.amount == dec(value) },
                          "\(value) did not survive migration exactly")
        }

        // --- Money added -------------------------------------------------------
        let added = try context.fetch(FetchDescriptor<MoneyAddedEntry>())
        XCTAssertEqual(added.count, 1)
        let refund = try XCTUnwrap(added.first { $0.id == fixture.refundID })
        XCTAssertEqual(refund.source, "Refund")
        XCTAssertEqual(refund.amount, dec("100.00"))
        XCTAssertEqual(refund.plan?.id, september.id,
                       "MoneyAddedEntry -> MonthlyPlan did not survive")

        // --- Totals still compute from the migrated graph ----------------------
        XCTAssertEqual(FinanceCalculator.totalSpent(for: september), dec("181.91"))
        XCTAssertEqual(FinanceCalculator.moneyAdded(for: september), dec("100.00"))
        XCTAssertEqual(FinanceCalculator.totalMoney(for: september), dec("2500.00"))
        XCTAssertEqual(FinanceCalculator.moneyRemaining(for: september), dec("2318.09"))
        XCTAssertEqual(FinanceCalculator.safeToSpend(for: september), dec("1318.09"))
        XCTAssertEqual(FinanceCalculator.uncategorizedSpent(for: september), dec("25.00"))

        // --- And no reviews appeared out of nowhere ----------------------------
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeeklyReview>()), 0,
                       "Migration invented review records")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyReview>()), 0,
                       "Migration invented review records")
    }

    /// A migrated month that was closed must still refuse financial writes.
    func testClosedMonthProtectionStillWorksAfterMigration() throws {
        let fixture = try writeV1Store()

        let container = try makeV2Container()
        let context = ModelContext(container)
        let september = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MonthlyPlan>())
                .first { $0.id == fixture.septemberID }
        )
        XCTAssertTrue(september.isClosed)

        let category = try XCTUnwrap(september.categories.first)

        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: dec("10"), date: date(20), merchant: "Nope",
                note: nil, category: category, plan: september, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: september.displayTitle)) }

        XCTAssertThrowsError(
            try MoneyAddedService.createEntry(
                amount: dec("10"), date: date(20), source: "Nope",
                note: nil, plan: september, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError,
                           .planIsClosed(monthTitle: september.displayTitle)) }

        XCTAssertThrowsError(
            try MonthlyPlanService.updateMoney(
                september, startingBalance: dec("1"), protectedAmount: .zero,
                context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError,
                           .planIsClosed(monthTitle: september.displayTitle)) }

        XCTAssertEqual(september.startingBalance, dec("2400.00"))
    }

    // MARK: - The migrated store is usable, not merely readable

    func testTheMigratedStoreAcceptsNewReviewsThatThenPersist() throws {
        let fixture = try writeV1Store()

        var weeklyID: UUID!
        var monthlyID: UUID!

        // Migrate, then write reviews into the migrated store.
        do {
            let container = try makeV2Container()
            let context = ModelContext(container)
            let september = try XCTUnwrap(
                try context.fetch(FetchDescriptor<MonthlyPlan>())
                    .first { $0.id == fixture.septemberID }
            )

            let weekly = try XCTUnwrap(
                try ReviewService.saveWeeklyReview(
                    for: september, weekStart: ReviewService.weekStart(for: date(9)),
                    note: "Cook at home more.", context: context
                )
            )
            weeklyID = weekly.id

            let monthly = try XCTUnwrap(
                try ReviewService.saveMonthlyReview(
                    for: september,
                    spentMoreThanExpected: "A little.",
                    avoidablePurchase: "The second coffee.",
                    worthwhilePurchase: "Groceries.",
                    changeNextMonth: "Plan meals.",
                    additionalNotes: nil,
                    context: context
                )
            )
            monthlyID = monthly.id
        }

        // Reopen once more: both reviews and all the old finance data are there.
        let container = try makeV2Container()
        let context = ModelContext(container)

        let weeklies = try context.fetch(FetchDescriptor<WeeklyReview>())
        XCTAssertEqual(weeklies.count, 1)
        XCTAssertEqual(weeklies.first?.id, weeklyID)
        XCTAssertEqual(weeklies.first?.note, "Cook at home more.")
        XCTAssertEqual(weeklies.first?.plan?.id, fixture.septemberID,
                       "WeeklyReview -> MonthlyPlan did not survive")

        let monthlies = try context.fetch(FetchDescriptor<MonthlyReview>())
        XCTAssertEqual(monthlies.count, 1)
        XCTAssertEqual(monthlies.first?.id, monthlyID)
        XCTAssertEqual(monthlies.first?.changeNextMonth, "Plan meals.")
        XCTAssertEqual(monthlies.first?.plan?.id, fixture.septemberID)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 5,
                       "Writing reviews disturbed the finance records")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 2)
    }

    /// Migrating twice must be a no-op, not a second transformation.
    func testReopeningAnAlreadyMigratedStoreChangesNothing() throws {
        try writeV1Store()

        do {
            let container = try makeV2Container()
            _ = ModelContext(container)
        }

        let container = try makeV2Container()
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetCategory>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()), 1)
    }

    // MARK: - A fresh V2 store, with no migration involved

    func testAFreshV2StoreWorksForFinanceAndReviews() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let plan = try MonthlyPlanService.createPlan(
            month: 9, year: 2026,
            startingBalance: dec("2400.00"), protectedAmount: dec("1000.00"),
            context: context
        )
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200.00"),
            type: .flexible, plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(4), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100.00"), date: date(15), source: "Refund",
            note: nil, plan: plan, context: context
        )
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: ReviewService.weekStart(for: date(9)),
            note: "Fine so far.", context: context
        )
        try ReviewService.saveMonthlyReview(
            for: plan, spentMoreThanExpected: "No.", avoidablePurchase: nil,
            worthwhilePurchase: nil, changeNextMonth: nil, additionalNotes: nil,
            context: context
        )

        XCTAssertEqual(FinanceCalculator.safeToSpend(for: plan), dec("1485.28"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeeklyReview>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyReview>()), 1)

        let tables = try Self.tableNames(in: storeURL)
        XCTAssertTrue(tables.contains("ZWEEKLYREVIEW"))
        XCTAssertTrue(tables.contains("ZMONTHLYREVIEW"))
    }

    // MARK: - Reading the store directly

    /// The column names of one table, read straight out of the file.
    private static func columnNames(of table: String, in url: URL) throws -> Set<String> {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            XCTFail("Could not open the store at \(url.path)")
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1,
                                 &statement, nil) == SQLITE_OK else {
            XCTFail("Could not read the columns of \(table)")
            return []
        }
        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 1) {
                names.insert(String(cString: text).uppercased())
            }
        }
        return names
    }

    /// Reads table names straight out of the SQLite file, so "this really is a
    /// V1 store" is a fact about the file on disk rather than about the model
    /// code that wrote it.
    private static func tableNames(in url: URL) throws -> Set<String> {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            XCTFail("Could not open the store at \(url.path)")
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table'"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            XCTFail("Could not read the store's table list")
            return []
        }
        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                names.insert(String(cString: text).uppercased())
            }
        }
        return names
    }
}

/// Reports built from a store that came through the V1 to V2 migration, rather
/// than from data created fresh. Migration succeeding at the persistence layer
/// does not by itself mean the graph reads correctly afterwards.
extension SchemaMigrationTests {

    func testAReportFromMigratedDataIsCorrect() throws {
        let fixture = try writeV1Store()

        let container = try makeV2Container()
        let context = ModelContext(container)
        let september = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MonthlyPlan>())
                .first { $0.id == fixture.septemberID }
        )

        let report = MonthlyReportBuilder.makeReport(for: september, context: context)

        XCTAssertEqual(report.month, 9)
        XCTAssertEqual(report.year, 2026)
        XCTAssertTrue(report.isClosed, "The migrated month lost its closed state")

        // The same figures the migration test asserts, arrived at through the
        // report rather than directly.
        XCTAssertEqual(report.summary.startingBalance, dec("2400.00"))
        XCTAssertEqual(report.summary.moneyAdded, dec("100.00"))
        XCTAssertEqual(report.summary.totalMoney, dec("2500.00"))
        XCTAssertEqual(report.summary.totalSpent, dec("181.91"))
        XCTAssertEqual(report.summary.moneyRemaining, dec("2318.09"))
        XCTAssertEqual(report.summary.safeToSpend, dec("1318.09"))

        // Relationships survived into the report's rows.
        XCTAssertEqual(report.expenses.count, 5)
        let chipotle = try XCTUnwrap(report.expenses.first { $0.merchant == "Chipotle" })
        XCTAssertEqual(chipotle.categoryName, "Eating Out")
        XCTAssertEqual(chipotle.amount, dec("14.72"))

        let orphan = try XCTUnwrap(report.expenses.first { $0.merchant == "Orphan" })
        XCTAssertEqual(orphan.categoryName, "Uncategorized")
        XCTAssertEqual(report.uncategorized?.spent, dec("25.00"))

        XCTAssertEqual(report.moneyAdded.count, 1)
        XCTAssertEqual(report.moneyAdded.first?.source, "Refund")
        XCTAssertEqual(report.categories.map(\.name), ["Eating Out"])

        // And it renders.
        let data = MonthlyReportPDFRenderer.render(report: report, level: .full)
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
        XCTAssertGreaterThan(data.count, 1000)
    }

    /// Reporting on a migrated store must not write to it either.
    func testReportingOnAMigratedStoreChangesNothing() throws {
        let fixture = try writeV1Store()

        let container = try makeV2Container()
        let context = ModelContext(container)
        let september = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MonthlyPlan>())
                .first { $0.id == fixture.septemberID }
        )

        let before = [
            try context.fetchCount(FetchDescriptor<MonthlyPlan>()),
            try context.fetchCount(FetchDescriptor<BudgetCategory>()),
            try context.fetchCount(FetchDescriptor<Expense>()),
            try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()),
            try context.fetchCount(FetchDescriptor<WeeklyReview>()),
            try context.fetchCount(FetchDescriptor<MonthlyReview>())
        ]

        let report = MonthlyReportBuilder.makeReport(for: september, context: context)
        _ = MonthlyReportPDFRenderer.render(report: report, level: .full)

        let after = [
            try context.fetchCount(FetchDescriptor<MonthlyPlan>()),
            try context.fetchCount(FetchDescriptor<BudgetCategory>()),
            try context.fetchCount(FetchDescriptor<Expense>()),
            try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()),
            try context.fetchCount(FetchDescriptor<WeeklyReview>()),
            try context.fetchCount(FetchDescriptor<MonthlyReview>())
        ]

        XCTAssertEqual(before, after, "Reporting changed a migrated store")
        XCTAssertTrue(september.isClosed, "Reporting reopened a migrated closed month")
    }
}
