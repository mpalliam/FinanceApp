import Foundation
import SwiftData

enum MonthlyPlanError: Error, Equatable {

    /// `month` was outside 1...12.
    case invalidMonth(Int)

    case negativeStartingBalance
    case negativeProtectedAmount

    /// A plan already exists for that calendar month.
    case planAlreadyExists(month: Int, year: Int)

    /// The month has been closed and is read-only.
    case planIsClosed(monthTitle: String)
}

extension MonthlyPlanError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .invalidMonth(let month):
            "\(month) is not a valid month. Use 1 through 12."
        case .negativeStartingBalance:
            "A starting balance cannot be negative."
        case .negativeProtectedAmount:
            "A protected amount cannot be negative."
        case .planAlreadyExists(let month, let year):
            "A plan already exists for \(month)/\(year)."
        case .planIsClosed(let monthTitle):
            "\(monthTitle) is closed. Closed months cannot be changed."
        }
    }
}

/// Creating a `MonthlyPlan` is the one place that has to enforce "one plan per
/// calendar month", and deliberately not a view, so that every screen creating
/// a month goes through the same guard.
///
/// There are two layers of protection, and both are wanted:
///
///   1. This service checks first and throws `planAlreadyExists`, which is what
///      the UI can turn into a readable message.
///   2. `MonthlyPlan.monthKey` is unique in the store, so a duplicate cannot be
///      persisted even if some future code path skips this service.
///
/// The service also generates the canonical key. No caller should build it.
enum MonthlyPlanService {

    @discardableResult
    static func createPlan(
        month: Int,
        year: Int,
        startingBalance: Decimal,
        protectedAmount: Decimal,
        context: ModelContext
    ) throws -> MonthlyPlan {

        guard (1...12).contains(month) else {
            throw MonthlyPlanError.invalidMonth(month)
        }
        guard startingBalance >= 0 else {
            throw MonthlyPlanError.negativeStartingBalance
        }
        guard protectedAmount >= 0 else {
            throw MonthlyPlanError.negativeProtectedAmount
        }

        // protectedAmount may exceed startingBalance: money added later in the
        // month can make that state legitimate.

        let plan = try insertPlan(
            month: month, year: year,
            startingBalance: startingBalance, protectedAmount: protectedAmount,
            context: context
        )
        try context.save()
        return plan
    }

    /// Validates and inserts, but does not save.
    ///
    /// Rollover needs to insert a plan and its copied categories and commit
    /// them together, so the save has to belong to the caller.
    private static func insertPlan(
        month: Int,
        year: Int,
        startingBalance: Decimal,
        protectedAmount: Decimal,
        context: ModelContext
    ) throws -> MonthlyPlan {

        guard (1...12).contains(month) else {
            throw MonthlyPlanError.invalidMonth(month)
        }
        guard startingBalance >= 0 else {
            throw MonthlyPlanError.negativeStartingBalance
        }
        guard protectedAmount >= 0 else {
            throw MonthlyPlanError.negativeProtectedAmount
        }
        guard try existingPlan(month: month, year: year, context: context) == nil else {
            throw MonthlyPlanError.planAlreadyExists(month: month, year: year)
        }

        let plan = MonthlyPlan(
            month: month,
            year: year,
            startingBalance: startingBalance,
            protectedAmount: protectedAmount
        )
        context.insert(plan)
        return plan
    }

    /// Changes the month's starting and protected money.
    ///
    /// Only these two are editable. month, year and monthKey stay `private(set)`
    /// on the model so they cannot drift apart, and nothing here weakens that:
    /// changing which month a plan is would be a different operation entirely.
    static func updateMoney(
        _ plan: MonthlyPlan,
        startingBalance: Decimal,
        protectedAmount: Decimal,
        context: ModelContext
    ) throws {
        try requireOpen(plan)

        guard startingBalance >= 0 else {
            throw MonthlyPlanError.negativeStartingBalance
        }
        guard protectedAmount >= 0 else {
            throw MonthlyPlanError.negativeProtectedAmount
        }

        // protectedAmount may still exceed startingBalance: money added later
        // in the month can make that legitimate.

        plan.startingBalance = startingBalance
        plan.protectedAmount = protectedAmount

        try context.save()
    }

    // MARK: - Closing

    /// Marks the month finalised. Nothing is deleted: a closed month keeps every
    /// expense, category and Money Added entry, and its totals still compute.
    /// It simply stops accepting changes.
    ///
    /// Idempotent -- closing an already closed month is a no-op, not an error.
    static func closePlan(_ plan: MonthlyPlan, context: ModelContext) throws {
        guard !plan.isClosed else { return }
        plan.isClosed = true
        try context.save()
    }

    /// Throws if the month is closed. The services call this so a write cannot
    /// slip past read-only UI through some other route.
    static func requireOpen(_ plan: MonthlyPlan) throws {
        guard !plan.isClosed else {
            throw MonthlyPlanError.planIsClosed(monthTitle: plan.displayTitle)
        }
    }

    // MARK: - Rollover

    /// The month after this one. Lives here rather than in a view so that
    /// December 2026 -> January 2027 cannot be got wrong by incrementing 12.
    static func nextMonth(after plan: MonthlyPlan) -> (month: Int, year: Int) {
        plan.month == 12 ? (1, plan.year + 1) : (plan.month + 1, plan.year)
    }

    /// What the next month should start with, given how this one went.
    static func rolloverDefaults(from plan: MonthlyPlan) -> RolloverDefaults {
        let next = nextMonth(after: plan)
        let remaining = FinanceCalculator.moneyRemaining(for: plan)

        return RolloverDefaults(
            month: next.month,
            year: next.year,
            // A MonthlyPlan cannot hold a negative starting balance, so an
            // overspent month starts the next one at zero. The real figure is
            // carried alongside so the UI can say so rather than pretend.
            startingBalance: max(remaining, 0),
            protectedAmount: plan.protectedAmount,
            previousMoneyRemaining: remaining,
            categoryCount: plan.categories.count
        )
    }

    /// Creates the following month, optionally copying this month's budgets.
    ///
    /// The plan and its copied categories are committed by a single save, so a
    /// failure part-way through leaves nothing behind rather than a month with
    /// four of its ten budgets.
    @discardableResult
    static func createNextPlan(
        from plan: MonthlyPlan,
        startingBalance: Decimal,
        protectedAmount: Decimal,
        copyCategories: Bool,
        context: ModelContext
    ) throws -> MonthlyPlan {

        let next = nextMonth(after: plan)

        let newPlan = try insertPlan(
            month: next.month,
            year: next.year,
            startingBalance: startingBalance,
            protectedAmount: protectedAmount,
            context: context
        )

        if copyCategories {
            // New objects, not the same ones: each month owns its budgets, so
            // editing October's Groceries must never touch September's.
            // Expenses and Money Added are deliberately not copied -- a new
            // month starts empty.
            for category in plan.categories {
                context.insert(
                    BudgetCategory(
                        name: category.name,
                        monthlyBudget: category.monthlyBudget,
                        type: category.type,
                        plan: newPlan
                    )
                )
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return newPlan
    }

    /// The existing plan for a calendar month, if there is one.
    ///
    /// Looks up by the canonical month key rather than comparing month and year
    /// separately, so the service and the store's uniqueness constraint agree on
    /// what "the same month" means.
    static func existingPlan(
        month: Int,
        year: Int,
        context: ModelContext
    ) throws -> MonthlyPlan? {
        let key = MonthlyPlan.makeMonthKey(month: month, year: year)
        var descriptor = FetchDescriptor<MonthlyPlan>(
            predicate: #Predicate { $0.monthKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}


/// What `Start Next Month` should suggest, and enough context for the UI to
/// explain any adjustment it had to make.
struct RolloverDefaults: Equatable {
    let month: Int
    let year: Int

    /// Never negative, because a MonthlyPlan cannot hold a negative balance.
    let startingBalance: Decimal

    let protectedAmount: Decimal

    /// The previous month's actual result, negative included. Kept so an
    /// overspent month is explained rather than silently rounded up to zero.
    let previousMoneyRemaining: Decimal

    let categoryCount: Int

    var startingBalanceWasClamped: Bool { previousMoneyRemaining < 0 }

    var monthTitle: String {
        var components = DateComponents()
        components.month = month
        components.year = year
        guard let date = Calendar.current.date(from: components) else {
            return "\(month)/\(year)"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
