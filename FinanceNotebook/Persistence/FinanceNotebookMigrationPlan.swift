import Foundation
import SwiftData

/// The ordered history of this app's schemas.
///
/// V1 is kept exactly as it was. It is not documentation -- it is the
/// description of what is actually on disk for anyone who has not upgraded yet,
/// and rewriting it would make the migration lie about where it started.
enum FinanceNotebookMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [
            FinanceNotebookSchemaV1.self,
            FinanceNotebookSchemaV2.self
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// V1 -> V2 adds two entities and changes nothing that already exists.
    ///
    /// Lightweight is only correct because no finance model was touched: not
    /// renamed, not reshaped, and given no new relationship. Adding an inverse
    /// array to MonthlyPlan would have made this a real data change rather than
    /// an additive one.
    ///
    /// This is verified rather than assumed -- SchemaMigrationTests writes a
    /// genuine V1 store to disk and reopens it through this plan, checking that
    /// every id, relationship, Decimal and closed flag survives.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FinanceNotebookSchemaV1.self,
        toVersion: FinanceNotebookSchemaV2.self
    )
}
