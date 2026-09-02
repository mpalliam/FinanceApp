import Foundation
import SwiftData

/// The first explicitly versioned schema.
///
/// The persistent model types are referenced here rather than nested inside
/// this enum. Nesting is what lets two versions of the same model coexist with
/// different definitions, and a future version that genuinely reshapes a model
/// will need it -- but nesting changes a type's Swift name, and SwiftData
/// derives entity identity from the type. Nesting the models at the moment
/// versioning is introduced would risk renaming every entity in the existing
/// store, which is the exact failure this versioning exists to prevent.
///
/// See Docs/SchemaVersioning.md before changing anything in this schema.
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
}
