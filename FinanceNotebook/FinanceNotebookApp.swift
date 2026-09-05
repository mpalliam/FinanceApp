import SwiftUI
import SwiftData

@main
struct FinanceNotebookApp: App {

    /// Local-only store on the device: no account, no networking, no CloudKit.
    ///
    /// The schema is taken from an explicit version rather than an ad-hoc model
    /// list, and the container is given a migration plan, so that a future model
    /// change migrates through a declared stage instead of letting SwiftData
    /// infer a mapping and silently discard rows.
    private let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV1.self)

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FinanceNotebookMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Could not create the local ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .onAppear {
                    DevelopmentSupport.applyLaunchArguments(
                        context: modelContainer.mainContext
                    )
                }
                #endif
        }
        .modelContainer(modelContainer)
    }
}
