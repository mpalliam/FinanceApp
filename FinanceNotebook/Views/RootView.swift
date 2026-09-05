import SwiftUI
import SwiftData

/// Chooses the month the app is working in and hands it to the expense list.
struct RootView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\MonthlyPlan.monthKey, order: .reverse)])
    private var plans: [MonthlyPlan]

    /// Resolved once, here, and handed to both tabs. That is what stops
    /// Expenses and Plan from ever showing different months.
    private var currentPlan: MonthlyPlan? {
        MonthlyPlan.current(from: plans)
    }

    var body: some View {
        if let plan = currentPlan {
            // The Tab type is iOS 18+, and this app targets iOS 17.
            TabView {
                ExpenseListView(plan: plan)
                    .tabItem { Label("Expenses", systemImage: "list.bullet") }

                MonthlyPlanView(plan: plan)
                    .tabItem { Label("Plan", systemImage: "chart.pie") }
            }
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
