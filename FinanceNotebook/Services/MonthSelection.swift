import Foundation
import Observation

/// Which month the whole app is looking at.
///
/// One instance is created by RootView and put in the environment, so Home,
/// Transactions and Plan all read the same value and cannot end up showing
/// different months.
///
/// The choice is remembered in UserDefaults rather than in SwiftData. It is a
/// UI preference, not a financial record, and the persistent schema stays
/// frozen.
@Observable
final class MonthSelection {

    private static let defaultsKey = "selectedMonthKey"

    /// The canonical "YYYY-MM" key of the chosen month, or nil to fall back to
    /// the current calendar month.
    var monthKey: String? {
        didSet {
            if let monthKey {
                UserDefaults.standard.set(monthKey, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    init() {
        monthKey = UserDefaults.standard.string(forKey: Self.defaultsKey)
    }

    /// Resolves the plan to work in, in the order a person would expect:
    /// the month they last chose, then the month it actually is, then the most
    /// recent month there is.
    func resolvePlan(from plans: [MonthlyPlan]) -> MonthlyPlan? {
        if let monthKey, let chosen = plans.first(where: { $0.monthKey == monthKey }) {
            return chosen
        }
        return MonthlyPlan.current(from: plans)
    }
}
