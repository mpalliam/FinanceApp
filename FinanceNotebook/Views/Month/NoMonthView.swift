import SwiftUI
import SwiftData

/// The app's first screen when nothing exists yet. Production, not a stub.
struct NoMonthView: View {

    @State private var isCreatingMonth = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Month Set Up", systemImage: "calendar.badge.plus")
            } description: {
                Text("Start your first monthly plan to begin tracking your money, expenses, and spending limits.")
            } actions: {
                Button("Start a Month") { isCreatingMonth = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("startAMonthButton")
            }
            .navigationTitle("Finance Notebook")
            .sheet(isPresented: $isCreatingMonth) {
                CreateMonthlyPlanView()
            }
        }
    }
}
