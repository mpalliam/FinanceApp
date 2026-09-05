import XCTest
import SwiftData
@testable import FinanceNotebook

final class ReviewServiceTests: XCTestCase {

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
        plan = nil; context = nil; container = nil
    }

    private func dec(_ v: String) -> Decimal { Decimal(string: v)! }

    private func date(_ day: Int, _ month: Int = 9, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func weeklyCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<WeeklyReview>())
    }

    private func monthlyCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MonthlyReview>())
    }

    // MARK: - Week normalisation

    /// Every day of a week must resolve to the same start, or reviews would
    /// silently split in two.
    func testEveryDayOfAWeekNormalisesToTheSameStart() {
        let midweek = date(9)
        let start = ReviewService.weekStart(for: midweek)

        for offset in 0..<7 {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            XCTAssertEqual(ReviewService.weekStart(for: day), start,
                           "Day \(offset) of the week normalised differently")
        }
    }

    func testWeekStartIsTheStartOfItsDay() {
        let start = ReviewService.weekStart(for: date(9))
        XCTAssertEqual(start, Calendar.current.startOfDay(for: start))
    }

    func testWeekStartFollowsTheCalendarsFirstWeekday() {
        let start = ReviewService.weekStart(for: date(9))
        XCTAssertEqual(Calendar.current.component(.weekday, from: start),
                       Calendar.current.firstWeekday,
                       "The week did not begin on the calendar's first weekday")
    }

    /// A week that straddles a month or a year must still be one week.
    func testWeeksSpanningMonthAndYearBoundariesStayWhole() {
        let calendar = Calendar.current

        let newYearsEve = date(31, 12, 2026)
        let newYearsDay = date(1, 1, 2027)
        if calendar.component(.weekOfYear, from: newYearsEve)
            == calendar.component(.weekOfYear, from: newYearsDay) {
            XCTAssertEqual(ReviewService.weekStart(for: newYearsEve),
                           ReviewService.weekStart(for: newYearsDay),
                           "A week spanning the year boundary split in two")
        }

        let endOfSeptember = date(30)
        let startOfOctober = date(1, 10, 2026)
        if calendar.component(.weekOfYear, from: endOfSeptember)
            == calendar.component(.weekOfYear, from: startOfOctober) {
            XCTAssertEqual(ReviewService.weekStart(for: endOfSeptember),
                           ReviewService.weekStart(for: startOfOctober),
                           "A week spanning the month boundary split in two")
        }
    }

    /// A leap day must not be a special case.
    func testLeapDayNormalisesLikeAnyOtherDay() {
        let leapDay = date(29, 2, 2028)
        let start = ReviewService.weekStart(for: leapDay)
        XCTAssertEqual(ReviewService.weekStart(for: start), start)
        XCTAssertLessThanOrEqual(start, leapDay)
    }

    // MARK: - Weekly reviews

    func testCreatesAWeeklyReview() throws {
        let review = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(9), note: "Cook at home more.",
                context: context
            )
        )

        XCTAssertEqual(review.note, "Cook at home more.")
        XCTAssertEqual(review.plan?.id, plan.id)
        XCTAssertEqual(review.weekStartDate, ReviewService.weekStart(for: date(9)))
        XCTAssertEqual(try weeklyCount(), 1)
    }

    func testTheNoteIsTrimmed() throws {
        let review = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(9), note: "  Cook at home.  ", context: context
            )
        )
        XCTAssertEqual(review.note, "Cook at home.")
    }

    /// Opening the form and leaving without writing anything must not litter
    /// the store with empty records.
    func testABlankNoteOnANewWeekCreatesNothing() throws {
        let result = try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(9), note: "   \n ", context: context
        )
        XCTAssertNil(result)
        XCTAssertEqual(try weeklyCount(), 0)
    }

    /// A second save for the same week updates the first, never adds another.
    func testSavingTwiceForTheSameWeekUpdatesTheSameReview() throws {
        let first = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(7), note: "First thought.", context: context
            )
        )
        let originalID = first.id
        let originalCreatedAt = first.createdAt

        let second = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(7), note: "Second thought.", context: context
            )
        )

        XCTAssertEqual(try weeklyCount(), 1, "A duplicate weekly review was created")
        XCTAssertEqual(second.id, originalID, "The review lost its identity")
        XCTAssertEqual(second.createdAt, originalCreatedAt, "createdAt was rewritten")
        XCTAssertEqual(second.note, "Second thought.")
        XCTAssertGreaterThanOrEqual(second.updatedAt, originalCreatedAt)
    }

    /// Two different days in the same week are the same week.
    func testDifferentDaysInOneWeekResolveToOneReview() throws {
        let start = ReviewService.weekStart(for: date(9))
        let laterInWeek = Calendar.current.date(byAdding: .day, value: 2, to: start)!

        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: start, note: "Monday.", context: context
        )
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: laterInWeek, note: "Wednesday.", context: context
        )

        XCTAssertEqual(try weeklyCount(), 1,
                       "Two days of the same week produced two reviews")
        XCTAssertEqual(
            try ReviewService.weeklyReview(for: plan, weekStart: start, context: context)?.note,
            "Wednesday."
        )
    }

    func testDifferentWeeksGetTheirOwnReviews() throws {
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(7), note: "Week one.", context: context
        )
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(21), note: "Week three.", context: context
        )

        XCTAssertEqual(try weeklyCount(), 2)
        let all = try ReviewService.weeklyReviews(for: plan, context: context)
        XCTAssertEqual(all.map(\.note), ["Week three.", "Week one."],
                       "Reviews should be listed newest week first")
    }

    /// The same week in two different months must not collide.
    func testTheSameWeekInAnotherMonthIsASeparateReview() throws {
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: false, context: context
        )
        let sharedWeek = ReviewService.weekStart(for: date(30))

        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: sharedWeek, note: "September's view.", context: context
        )
        try ReviewService.saveWeeklyReview(
            for: october, weekStart: sharedWeek, note: "October's view.", context: context
        )

        XCTAssertEqual(try weeklyCount(), 2, "Reviews collided across months")
        XCTAssertEqual(
            try ReviewService.weeklyReview(for: plan, weekStart: sharedWeek,
                                           context: context)?.note,
            "September's view."
        )
        XCTAssertEqual(
            try ReviewService.weeklyReview(for: october, weekStart: sharedWeek,
                                           context: context)?.note,
            "October's view."
        )
    }

    func testWeeklyReviewsAreScopedToTheirMonth() throws {
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: false, context: context
        )
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(7), note: "September.", context: context
        )

        XCTAssertEqual(try ReviewService.weeklyReviews(for: plan, context: context).count, 1)
        XCTAssertEqual(try ReviewService.weeklyReviews(for: october, context: context).count, 0,
                       "October showed September's review")
    }

    func testClearingANoteOnAnExistingReviewKeepsTheRecord() throws {
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(7), note: "Something.", context: context
        )
        let cleared = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(7), note: "", context: context
            )
        )
        XCTAssertNil(cleared.note, "Clearing the note should empty it, not delete the week")
        XCTAssertEqual(try weeklyCount(), 1)
    }

    func testDeletingAWeeklyReviewLeavesTheMonthAlone() throws {
        let review = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(7), note: "Something.", context: context
            )
        )
        try ReviewService.deleteWeeklyReview(review, context: context)

        XCTAssertEqual(try weeklyCount(), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyPlan>()), 1,
                       "Deleting a review deleted the month")
    }

    // MARK: - Monthly reflection

    func testCreatesAMonthlyReflection() throws {
        let review = try XCTUnwrap(
            try ReviewService.saveMonthlyReview(
                for: plan,
                spentMoreThanExpected: "A bit.",
                avoidablePurchase: "The second coffee.",
                worthwhilePurchase: "Groceries.",
                changeNextMonth: "Plan meals.",
                additionalNotes: nil,
                context: context
            )
        )

        XCTAssertEqual(review.spentMoreThanExpected, "A bit.")
        XCTAssertEqual(review.changeNextMonth, "Plan meals.")
        XCTAssertNil(review.additionalNotes)
        XCTAssertEqual(review.plan?.id, plan.id)
        XCTAssertEqual(try monthlyCount(), 1)
    }

    func testPartialAnswersAreAllowed() throws {
        let review = try XCTUnwrap(
            try ReviewService.saveMonthlyReview(
                for: plan, spentMoreThanExpected: nil, avoidablePurchase: nil,
                worthwhilePurchase: "The winter coat.", changeNextMonth: nil,
                additionalNotes: nil, context: context
            )
        )
        XCTAssertEqual(review.worthwhilePurchase, "The winter coat.")
        XCTAssertNil(review.spentMoreThanExpected)
    }

    func testAllBlankAnswersCreateNothing() throws {
        let result = try ReviewService.saveMonthlyReview(
            for: plan, spentMoreThanExpected: "  ", avoidablePurchase: nil,
            worthwhilePurchase: "", changeNextMonth: "\n", additionalNotes: nil,
            context: context
        )
        XCTAssertNil(result)
        XCTAssertEqual(try monthlyCount(), 0)
    }

    func testAMonthHasAtMostOneReflection() throws {
        let first = try XCTUnwrap(
            try ReviewService.saveMonthlyReview(
                for: plan, spentMoreThanExpected: "Yes.", avoidablePurchase: nil,
                worthwhilePurchase: nil, changeNextMonth: nil, additionalNotes: nil,
                context: context
            )
        )
        let originalID = first.id
        let originalCreatedAt = first.createdAt

        let second = try XCTUnwrap(
            try ReviewService.saveMonthlyReview(
                for: plan, spentMoreThanExpected: "No, actually.",
                avoidablePurchase: "The taxi.", worthwhilePurchase: nil,
                changeNextMonth: nil, additionalNotes: nil, context: context
            )
        )

        XCTAssertEqual(try monthlyCount(), 1, "A second reflection was created")
        XCTAssertEqual(second.id, originalID, "The reflection lost its identity")
        XCTAssertEqual(second.createdAt, originalCreatedAt, "createdAt was rewritten")
        XCTAssertEqual(second.spentMoreThanExpected, "No, actually.")
        XCTAssertEqual(second.avoidablePurchase, "The taxi.")
    }

    func testReflectionsAreScopedToTheirMonth() throws {
        let october = try MonthlyPlanService.createNextPlan(
            from: plan, startingBalance: dec("100"), protectedAmount: .zero,
            copyCategories: false, context: context
        )
        try ReviewService.saveMonthlyReview(
            for: plan, spentMoreThanExpected: "September.", avoidablePurchase: nil,
            worthwhilePurchase: nil, changeNextMonth: nil, additionalNotes: nil,
            context: context
        )

        XCTAssertNotNil(try ReviewService.monthlyReview(for: plan, context: context))
        XCTAssertNil(try ReviewService.monthlyReview(for: october, context: context),
                     "October showed September's reflection")
        XCTAssertEqual(try monthlyCount(), 1)
    }

    // MARK: - Closed months

    /// The distinction this milestone rests on: closing settles the money, not
    /// what the user thinks about it.
    func testAClosedMonthStillAcceptsReviewsWhileRefusingFinancialWrites() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("200"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("14.72"), date: date(4), merchant: "Chipotle",
            note: nil, category: category, plan: plan, context: context
        )
        try MonthlyPlanService.closePlan(plan, context: context)

        // Money is settled.
        XCTAssertThrowsError(
            try ExpenseService.createExpense(
                amount: dec("10"), date: date(5), merchant: "Nope",
                note: nil, category: category, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? ExpenseError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertThrowsError(
            try MoneyAddedService.createEntry(
                amount: dec("10"), date: date(5), source: "Nope",
                note: nil, plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? MoneyAddedError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertThrowsError(
            try BudgetCategoryService.createCategory(
                name: "Nope", monthlyBudget: dec("1"), type: .flexible,
                plan: plan, context: context
            )
        ) { XCTAssertEqual($0 as? BudgetCategoryError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        XCTAssertThrowsError(
            try MonthlyPlanService.updateMoney(
                plan, startingBalance: dec("1"), protectedAmount: .zero, context: context
            )
        ) { XCTAssertEqual($0 as? MonthlyPlanError,
                           .planIsClosed(monthTitle: plan.displayTitle)) }

        // Reflection is not.
        let weekly = try XCTUnwrap(
            try ReviewService.saveWeeklyReview(
                for: plan, weekStart: date(7), note: "Looking back.", context: context
            )
        )
        XCTAssertEqual(weekly.note, "Looking back.")

        let monthly = try XCTUnwrap(
            try ReviewService.saveMonthlyReview(
                for: plan, spentMoreThanExpected: "Yes.", avoidablePurchase: nil,
                worthwhilePurchase: nil, changeNextMonth: "Eat in more.",
                additionalNotes: nil, context: context
            )
        )
        XCTAssertEqual(monthly.changeNextMonth, "Eat in more.")

        // Editing them afterwards is fine too.
        try ReviewService.saveWeeklyReview(
            for: plan, weekStart: date(7), note: "Revised.", context: context
        )
        XCTAssertEqual(weekly.note, "Revised.")

        // And none of it touched the ledger.
        XCTAssertEqual(FinanceCalculator.totalSpent(for: plan), dec("14.72"))
        XCTAssertTrue(plan.isClosed)
    }

    // MARK: - The numbers a review shows

    /// Review screens must read the calculator rather than doing their own sums.
    func testTheReviewSummaryComesFromTheCalculator() throws {
        let category = try BudgetCategoryService.createCategory(
            name: "Eating Out", monthlyBudget: dec("700"), type: .flexible,
            plan: plan, context: context
        )
        try ExpenseService.createExpense(
            amount: dec("624"), date: date(4), merchant: "Various",
            note: nil, category: category, plan: plan, context: context
        )
        try MoneyAddedService.createEntry(
            amount: dec("100"), date: date(15), source: "Refund",
            note: nil, plan: plan, context: context
        )

        let summary = FinanceCalculator.summary(for: plan)
        XCTAssertEqual(summary.totalMoney, dec("2500"))
        XCTAssertEqual(summary.totalSpent, dec("624"))
        XCTAssertEqual(summary.moneyRemaining, dec("1876"))
        XCTAssertEqual(summary.safeToSpend, dec("876"))
    }
}
