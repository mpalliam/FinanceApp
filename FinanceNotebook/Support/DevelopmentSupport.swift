#if DEBUG
import Foundation
import SwiftData

/// Launch-argument hooks so UI tests can put the store into a known state
/// without the app exposing test controls in its real interface.
///
/// DEBUG only: none of this exists in a release build.
enum DevelopmentSupport {

    static let resetArgument = "-uiTestReset"
    static let seedMonthArgument = "-uiTestSeedMonth"
    static let seedExpenseArgument = "-uiTestSeedExpense"
    static let seedMoneyAddedArgument = "-uiTestSeedMoneyAdded"
    static let seedPreviousMonthArgument = "-uiTestSeedPreviousMonth"
    static let seedUncategorizedArgument = "-uiTestSeedUncategorized"
    static let clearSelectionArgument = "-uiTestClearMonthSelection"
    static let seedShowcaseArgument = "-uiTestSeedShowcase"

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func applyLaunchArguments(context: ModelContext) {
        if arguments.contains(resetArgument) {
            deleteEverything(context: context)
        }
        if arguments.contains(clearSelectionArgument) || arguments.contains(resetArgument) {
            // The chosen month lives in UserDefaults, which survives a store
            // reset, so a test starting from empty has to clear it too.
            UserDefaults.standard.removeObject(forKey: "selectedMonthKey")
        }
        if arguments.contains(seedShowcaseArgument) {
            seedShowcase(context: context)
        }
        if arguments.contains(seedPreviousMonthArgument) {
            seedPreviousMonth(context: context)
        }
        if arguments.contains(seedMonthArgument) {
            let plan = seedCurrentMonth(context: context)
            if arguments.contains(seedExpenseArgument), let plan {
                seedSampleExpense(in: plan, context: context)
            }
            if arguments.contains(seedMoneyAddedArgument), let plan {
                seedSampleMoneyAdded(in: plan, context: context)
            }
            if arguments.contains(seedUncategorizedArgument), let plan {
                seedUncategorizedExpenses(in: plan, context: context)
            }
        }
    }

    /// The dataset used for App Store screenshots.
    ///
    /// Fictional on purpose: no real merchant tied to the user, no private
    /// notes, and figures chosen so every screen agrees with every other one.
    ///
    ///     starting 2,400 - protected 1,000 + added 100 - spent 624 = 876 safe
    ///
    /// DEBUG only, like everything else here, so it cannot be reached by
    /// anyone running a shipped build.
    static func seedShowcase(context: ModelContext) {
        let calendar = Calendar.current
        do {
            guard try MonthlyPlanService.existingPlan(
                month: 9, year: 2026, context: context
            ) == nil else { return }

            let plan = try MonthlyPlanService.createPlan(
                month: 9, year: 2026,
                startingBalance: Decimal(string: "2400.00") ?? .zero,
                protectedAmount: Decimal(string: "1000.00") ?? .zero,
                context: context
            )

            let budgets = [
                ("Groceries", "400.00"), ("Eating Out", "200.00"),
                ("Transportation", "150.00"), ("Entertainment", "120.00")
            ]
            var categories: [String: BudgetCategory] = [:]
            for (name, budget) in budgets {
                categories[name] = try BudgetCategoryService.createCategory(
                    name: name,
                    monthlyBudget: Decimal(string: budget) ?? .zero,
                    type: .flexible, plan: plan, context: context
                )
            }

            // Totals 624.00 across the four categories.
            let expenses: [(String, String, String, Int)] = [
                ("Groceries", "Farmers Market", "62.40", 2),
                ("Groceries", "Corner Grocer", "48.15", 5),
                ("Groceries", "Whole Foods", "96.30", 9),
                ("Groceries", "Corner Grocer", "37.20", 14),
                ("Eating Out", "Noodle Bar", "24.80", 4),
                ("Eating Out", "Cafe Lumen", "16.45", 8),
                ("Eating Out", "Taqueria Norte", "31.75", 13),
                ("Transportation", "Metro Card", "45.00", 3),
                ("Transportation", "City Rideshare", "28.60", 11),
                ("Transportation", "Parking Garage", "18.00", 16),
                ("Entertainment", "Film House", "22.00", 6),
                ("Entertainment", "Record Shop", "34.90", 12),
                ("Entertainment", "Bookstore", "158.45", 15)
            ]
            for (category, merchant, amount, day) in expenses {
                guard let date = calendar.date(
                    from: DateComponents(year: 2026, month: 9, day: day)
                ), let category = categories[category] else { continue }
                try ExpenseService.createExpense(
                    amount: Decimal(string: amount) ?? .zero,
                    date: date, merchant: merchant, note: nil,
                    category: category, plan: plan, context: context
                )
            }

            if let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)) {
                try MoneyAddedService.createEntry(
                    amount: Decimal(string: "100.00") ?? .zero,
                    date: date, source: "Refund", note: nil,
                    plan: plan, context: context
                )
            }

            if let week = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)) {
                _ = try ReviewService.saveWeeklyReview(
                    for: plan, weekStart: week,
                    note: "Groceries are running ahead of plan. Cooking at home more next week.",
                    context: context
                )
            }

            _ = try ReviewService.saveMonthlyReview(
                for: plan,
                spentMoreThanExpected: "Entertainment, mostly one large book order.",
                avoidablePurchase: "The second rideshare of the month.",
                worthwhilePurchase: "The farmers market trip covered most of two weeks.",
                changeNextMonth: "Move 50 from Entertainment into Groceries.",
                additionalNotes: nil,
                context: context
            )
        } catch {
            print("Seeding showcase failed: \(error.localizedDescription)")
        }
    }

    /// A single Chipotle expense, so edit and delete tests start from a known
    /// record instead of re-creating one through the UI each time.
    static func seedSampleExpense(in plan: MonthlyPlan, context: ModelContext) {
        guard plan.expenses.isEmpty, let category = plan.categories.first else { return }
        do {
            try ExpenseService.createExpense(
                amount: Decimal(string: "14.72") ?? .zero,
                date: plan.contains(Date()) ? Date() : (plan.monthInterval?.start ?? Date()),
                merchant: "Chipotle",
                note: nil,
                category: category,
                plan: plan,
                context: context
            )
        } catch {
            print("Seeding expense failed: \(error.localizedDescription)")
        }
    }

    /// Creates a plan for the current calendar month plus one category, so a UI
    /// test can go straight to adding an expense. Seeding the *current* month
    /// keeps default expense dates inside the plan's month as time passes.
    @discardableResult
    static func seedCurrentMonth(context: ModelContext) -> MonthlyPlan? {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        do {
            let plan: MonthlyPlan
            if let existing = try MonthlyPlanService.existingPlan(
                month: month, year: year, context: context
            ) {
                plan = existing
            } else {
                plan = try MonthlyPlanService.createPlan(
                    month: month,
                    year: year,
                    startingBalance: Decimal(string: "2400.00") ?? .zero,
                    protectedAmount: Decimal(string: "1000.00") ?? .zero,
                    context: context
                )
            }

            if plan.categories.isEmpty {
                try BudgetCategoryService.createCategory(
                    name: "Eating Out",
                    monthlyBudget: Decimal(string: "200.00") ?? .zero,
                    type: .flexible,
                    plan: plan,
                    context: context
                )
            }
            return plan
        } catch {
            print("Seeding failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// A single Refund entry, so edit and delete tests start from a known
    /// record. The add test deliberately does not use this: it types its own.
    static func seedSampleMoneyAdded(in plan: MonthlyPlan, context: ModelContext) {
        guard plan.moneyAdded.isEmpty else { return }
        do {
            try MoneyAddedService.createEntry(
                amount: Decimal(string: "100.00") ?? .zero,
                date: plan.contains(Date()) ? Date() : (plan.monthInterval?.start ?? Date()),
                source: "Refund",
                note: nil,
                plan: plan,
                context: context
            )
        } catch {
            print("Seeding money added failed: \(error.localizedDescription)")
        }
    }

    /// The month before this one, so month-switching tests have two to move
    /// between with visibly different figures.
    @discardableResult
    static func seedPreviousMonth(context: ModelContext) -> MonthlyPlan? {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let previous = month == 1 ? (month: 12, year: year - 1) : (month: month - 1, year: year)

        do {
            if let existing = try MonthlyPlanService.existingPlan(
                month: previous.month, year: previous.year, context: context
            ) {
                return existing
            }
            return try MonthlyPlanService.createPlan(
                month: previous.month,
                year: previous.year,
                startingBalance: Decimal(string: "999.00") ?? .zero,
                protectedAmount: Decimal(string: "500.00") ?? .zero,
                context: context
            )
        } catch {
            print("Seeding previous month failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Three expenses whose category is then deleted, which is the only way
    /// uncategorized spending actually arises.
    static func seedUncategorizedExpenses(in plan: MonthlyPlan, context: ModelContext) {
        do {
            let doomed = try BudgetCategoryService.createCategory(
                name: "Old Category", monthlyBudget: .zero, type: .flexible,
                plan: plan, context: context
            )
            let day = plan.contains(Date()) ? Date() : (plan.monthInterval?.start ?? Date())
            for (name, amount) in [("Taco Bell", "9.88"), ("Uber", "21.50"),
                                   ("Newsstand", "4.25")] {
                try ExpenseService.createExpense(
                    amount: Decimal(string: amount) ?? .zero, date: day,
                    merchant: name, note: nil, category: doomed,
                    plan: plan, context: context
                )
            }
            try BudgetCategoryService.deleteCategory(doomed, context: context)
        } catch {
            print("Seeding uncategorized failed: \(error.localizedDescription)")
        }
    }

    static func deleteEverything(context: ModelContext) {
        // Children before parents, saving between each level. Deleting plans
        // first cascades to their expenses, and a list fetched before that
        // cascade then contains objects whose backing data is gone -- SwiftData
        // traps on those rather than skipping them.
        do {
            try deleteAll(WeeklyReview.self, in: context)
            try deleteAll(MonthlyReview.self, in: context)
            try context.save()

            try deleteAll(Expense.self, in: context)
            try deleteAll(MoneyAddedEntry.self, in: context)
            try context.save()

            try deleteAll(BudgetCategory.self, in: context)
            try context.save()

            try deleteAll(MonthlyPlan.self, in: context)
            try context.save()
        } catch {
            print("Reset failed: \(error)")
        }
    }

    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type, in context: ModelContext
    ) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}
#endif
