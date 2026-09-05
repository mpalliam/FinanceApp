import Foundation
import SwiftData

enum MonthlyPlanError: Error, Equatable {

    /// `month` was outside 1...12.
    case invalidMonth(Int)

    case negativeStartingBalance
    case negativeProtectedAmount

    /// A plan already exists for that calendar month.
    case planAlreadyExists(month: Int, year: Int)
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
        try context.save()
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
