import Foundation
import SwiftData

/// The schema as it stood through Milestone 5, before reviews existed.
///
/// The models are nested copies rather than references to the app's live types,
/// and that is not stylistic. V2 adds `WeeklyReview.plan`, and SwiftData
/// synthesises the inverse of that relationship onto `MonthlyPlan` whether or
/// not an array is declared there. While V1 pointed at the same `MonthlyPlan`
/// type the app uses, V1 quietly absorbed the review relationship too and
/// became indistinguishable from V2 -- SwiftData refused the migration plan
/// outright with "Duplicate version checksums detected."
///
/// Owning its own copies is what lets V1 keep describing the schema that is
/// actually on disk for anyone who has not upgraded. Nothing here is used by
/// the running app; it exists so the migration knows where it started.
///
/// `CategoryType` is deliberately shared with the live model rather than
/// duplicated: it is a Codable enum, not an entity, so it takes no part in
/// schema identity, and sharing it guarantees both versions encode it
/// identically.
///
/// This file is frozen. See Docs/SchemaVersioning.md.
enum FinanceNotebookSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            MonthlyPlan.self,
            BudgetCategory.self,
            Expense.self,
            MoneyAddedEntry.self
        ]
    }

    @Model
    final class MonthlyPlan {

        @Attribute(.unique) var id: UUID = UUID()
        @Attribute(.unique) var monthKey: String = ""

        var month: Int = 1
        var year: Int = 2000
        var startingBalance: Decimal = Decimal.zero
        var protectedAmount: Decimal = Decimal.zero
        var isClosed: Bool = false
        var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.plan)
        var categories: [BudgetCategory] = []

        @Relationship(deleteRule: .cascade, inverse: \Expense.plan)
        var expenses: [Expense] = []

        @Relationship(deleteRule: .cascade, inverse: \MoneyAddedEntry.plan)
        var moneyAdded: [MoneyAddedEntry] = []

        init(
            month: Int,
            year: Int,
            startingBalance: Decimal,
            protectedAmount: Decimal
        ) {
            self.id = UUID()
            self.month = month
            self.year = year
            self.monthKey = String(format: "%04d-%02d", year, month)
            self.startingBalance = startingBalance
            self.protectedAmount = protectedAmount
            self.isClosed = false
            self.createdAt = Date()
        }
    }

    @Model
    final class BudgetCategory {

        @Attribute(.unique) var id: UUID = UUID()

        var name: String = ""
        var monthlyBudget: Decimal = Decimal.zero
        var type: CategoryType = CategoryType.flexible

        var plan: MonthlyPlan?

        @Relationship(deleteRule: .nullify, inverse: \Expense.category)
        var expenses: [Expense] = []

        init(
            name: String,
            monthlyBudget: Decimal,
            type: CategoryType,
            plan: MonthlyPlan? = nil
        ) {
            self.id = UUID()
            self.name = name
            self.monthlyBudget = monthlyBudget
            self.type = type
            self.plan = plan
        }
    }

    @Model
    final class Expense {

        @Attribute(.unique) var id: UUID = UUID()

        var amount: Decimal = Decimal.zero
        var date: Date = Date()
        var merchant: String = ""
        var note: String?
        var createdAt: Date = Date()

        var category: BudgetCategory?
        var plan: MonthlyPlan?

        init(
            amount: Decimal,
            date: Date,
            merchant: String,
            note: String? = nil,
            category: BudgetCategory? = nil,
            plan: MonthlyPlan? = nil
        ) {
            self.id = UUID()
            self.amount = abs(amount)
            self.date = date
            self.merchant = merchant
            self.note = note
            self.category = category
            self.plan = plan
            self.createdAt = Date()
        }
    }

    @Model
    final class MoneyAddedEntry {

        @Attribute(.unique) var id: UUID = UUID()

        var amount: Decimal = Decimal.zero
        var date: Date = Date()
        var source: String = ""
        var note: String?
        var createdAt: Date = Date()

        var plan: MonthlyPlan?

        init(
            amount: Decimal,
            date: Date,
            source: String,
            note: String? = nil,
            plan: MonthlyPlan? = nil
        ) {
            self.id = UUID()
            self.amount = abs(amount)
            self.date = date
            self.source = source
            self.note = note
            self.plan = plan
            self.createdAt = Date()
        }
    }
}
