import Foundation
import SwiftData

/// Adds the review entities. Nothing else.
///
/// The four finance models are the *same Swift types* V1 lists -- not renamed,
/// not nested, not reshaped. That is what makes this the smallest possible
/// change: V1 and V2 describe identical finance entities, and V2 simply knows
/// about two more.
///
/// It is also why `MonthlyPlan` has no `weeklyReviews` or `monthlyReview`
/// array. Adding one would alter MonthlyPlan, and V1 still points at that same
/// type, so V1 would quietly stop describing the schema it was written for.
/// The reviews reference their plan one-directionally instead, and
/// ReviewService fetches them by predicate.
///
/// See Docs/SchemaVersioning.md before changing anything here.
enum FinanceNotebookSchemaV2: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            // Unchanged from V1.
            MonthlyPlan.self,
            BudgetCategory.self,
            Expense.self,
            MoneyAddedEntry.self,

            // New in V2.
            WeeklyReview.self,
            MonthlyReview.self
        ]
    }
}
