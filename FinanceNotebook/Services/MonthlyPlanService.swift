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
/// calendar month". SwiftData cannot express uniqueness across two attributes,
/// so the rule is checked here rather than in the schema -- and deliberately
/// not in a view, so that every screen that creates a month goes through the
/// same guard.
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

    /// The existing plan for a calendar month, if there is one.
    static func existingPlan(
        month: Int,
        year: Int,
        context: ModelContext
    ) throws -> MonthlyPlan? {
        var descriptor = FetchDescriptor<MonthlyPlan>(
            predicate: #Predicate { $0.month == month && $0.year == year }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
