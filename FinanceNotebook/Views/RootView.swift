import SwiftUI
import SwiftData

/// Resolves the month the app is working in and hands the same plan to every
/// tab. One resolution point is what stops Home, Transactions and Plan from
/// ever showing different months.
struct RootView: View {

    @Query(sort: [SortDescriptor(\MonthlyPlan.monthKey, order: .reverse)])
    private var plans: [MonthlyPlan]

    @State private var selection = MonthSelection()

    private var selectedPlan: MonthlyPlan? {
        selection.resolvePlan(from: plans)
    }

    var body: some View {
        Group {
            if let plan = selectedPlan {
                // The Tab type is iOS 18+, and this app targets iOS 17.
                TabView {
                    HomeView(plan: plan)
                        .tabItem { Label("Home", systemImage: "house") }

                    ExpenseListView(plan: plan)
                        .tabItem { Label("Transactions", systemImage: "list.bullet") }

                    MonthlyPlanView(plan: plan)
                        .tabItem { Label("Plan", systemImage: "chart.pie") }
                }
            } else {
                NoMonthView()
            }
        }
        .environment(selection)
    }
}
