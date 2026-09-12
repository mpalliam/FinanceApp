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
    ///
    /// nil when the store could not be opened. Launching into an explanation
    /// beats crashing on every launch with nothing the user can act on.
    private static let modelContainer: ModelContainer? = {
        let schema = Schema(versionedSchema: FinanceNotebookSchemaV2.self)

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: FinanceNotebookMigrationPlan.self,
                configurations: [configuration]
            )
            #if DEBUG
            // Here, not in init() or onAppear. SwiftUI initialises an App more
            // than once, so an instance property rebuilt the container and ran
            // the seeding again against a second container over the same file;
            // and onAppear ran it after RootView had already resolved a plan,
            // leaving that view holding an object the reset had just deleted.
            // A static let runs exactly once, before any view can query.
            // A context of its own: a static initialiser is not guaranteed to run
            // on the main actor, and mainContext expects to be used there.
            DevelopmentSupport.applyLaunchArguments(context: ModelContext(container))
            #endif
            return container
        } catch {
            // Deliberately not logged: the error can carry store paths and
            // column detail, and this is financial data.
            return nil
        }
    }()

    var body: some Scene {
        WindowGroup {
            if let container = Self.modelContainer {
                RootView()
                    .modelContainer(container)
            } else {
                StoreUnavailableView()
            }
        }
    }
}
