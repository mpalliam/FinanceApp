import Foundation
import SwiftData

/// The ordered history of this app's schemas.
///
/// There is only one version so far, so there are no stages yet. That is not a
/// gap to be filled: a stage is only ever added alongside a real schema change.
///
/// When the model does change, the change goes into a new
/// `FinanceNotebookSchemaV2` and a stage is appended here -- the previous
/// version is never edited in place. See Docs/SchemaVersioning.md.
enum FinanceNotebookMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [FinanceNotebookSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
