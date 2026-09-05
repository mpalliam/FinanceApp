import SwiftUI
import SwiftData

/// Chooses the month the app is working in and hands it to the expense list.
struct RootView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\MonthlyPlan.monthKey, order: .reverse)])
    private var plans: [MonthlyPlan]

    /// The plan for the current calendar month if there is one, otherwise the
    /// most recent plan. Month selection proper comes in a later milestone.
    private var currentPlan: MonthlyPlan? {
        let calendar = Calendar.current
        let key = MonthlyPlan.makeMonthKey(
            month: calendar.component(.month, from: Date()),
            year: calendar.component(.year, from: Date())
        )
        return plans.first { $0.monthKey == key } ?? plans.first
    }

    var body: some View {
        if let plan = currentPlan {
            ExpenseListView(plan: plan)
        } else {
            NoMonthView()
        }
    }
}

/// Shown when no MonthlyPlan exists at all. The month-creation workflow is a
/// later milestone, so this explains rather than offers.
struct NoMonthView: View {

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Month Set Up", systemImage: "calendar.badge.plus")
            } description: {
                Text("Create a monthly plan before recording expenses.")
            } actions: {
                #if DEBUG
                // Temporary development affordance. Month creation still goes
                // through MonthlyPlanService, never straight into the context.
                Button("Create Sample Month") {
                    DevelopmentSupport.seedCurrentMonth(context: context)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("createSampleMonthButton")
                #endif
            }
            .navigationTitle("Expenses")
        }
    }
}
