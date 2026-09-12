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
                // Two sentences, not a carousel. The second one is there
                // because manual entry is the design, and a new user should
                // read it as the point rather than as a missing feature.
                Text("""
                     Set the money you have available, protect the amount you \
                     don't want to spend, and track the rest as you go.

                     Finance Notebook is manual by design: nothing is imported \
                     from a bank, so what you record is what you meant to record.
                     """)
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
