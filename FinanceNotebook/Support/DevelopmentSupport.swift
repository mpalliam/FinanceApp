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
