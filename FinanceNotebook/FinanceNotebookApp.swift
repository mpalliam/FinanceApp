import SwiftUI
import SwiftData

@main
struct FinanceNotebookApp: App {

    /// Local-only store on the device: no account, no networking, no CloudKit.
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            MonthlyPlan.self,
            BudgetCategory.self,
            Expense.self,
            MoneyAddedEntry.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the local ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            DevDataView()
        }
        .modelContainer(modelContainer)
    }
}
