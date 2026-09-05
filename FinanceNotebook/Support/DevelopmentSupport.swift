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

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func applyLaunchArguments(context: ModelContext) {
        if arguments.contains(resetArgument) {
            deleteEverything(context: context)
        }
        if arguments.contains(seedMonthArgument) {
            let plan = seedCurrentMonth(context: context)
            if arguments.contains(seedExpenseArgument), let plan {
                seedSampleExpense(in: plan, context: context)
            }
            if arguments.contains(seedMoneyAddedArgument), let plan {
                seedSampleMoneyAdded(in: plan, context: context)
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

    static func deleteEverything(context: ModelContext) {
        do {
            // Deleting the plans cascades to categories, expenses and additions.
            for plan in try context.fetch(FetchDescriptor<MonthlyPlan>()) {
                context.delete(plan)
            }
            // Anything orphaned by an earlier nullify.
            for expense in try context.fetch(FetchDescriptor<Expense>()) {
                context.delete(expense)
            }
            try context.save()
        } catch {
            print("Reset failed: \(error.localizedDescription)")
        }
    }
}
#endif
