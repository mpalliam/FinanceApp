import SwiftUI
import SwiftData

/// The month title in the toolbar, which opens the month list.
///
/// One component, used by all three tabs, so there is a single place that knows
/// how months are chosen.
struct MonthSelectorButton: View {

    let plan: MonthlyPlan

    @State private var isChoosing = false

    var body: some View {
        Button {
            isChoosing = true
        } label: {
            HStack(spacing: 4) {
                Text(plan.displayTitle)
                    .font(.subheadline.weight(.medium))
                if plan.isClosed {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .accessibilityIdentifier("monthSelectorButton")
        .accessibilityLabel("Select month, currently \(plan.displayTitle)")
        .sheet(isPresented: $isChoosing) {
            MonthListView()
        }
    }
}

/// Every month that exists, newest first.
struct MonthListView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(MonthSelection.self) private var selection

    @Query(sort: [SortDescriptor(\MonthlyPlan.monthKey, order: .reverse)])
    private var plans: [MonthlyPlan]

    @State private var isCreatingMonth = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(plans) { plan in
                        Button {
                            selection.monthKey = plan.monthKey
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.displayTitle)
                                        .foregroundStyle(.primary)
                                    if plan.isClosed {
                                        Text("Closed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if plan.monthKey == selection.monthKey {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("monthOption-\(plan.displayTitle)")
                    }
                }

                Section {
                    Button("Start Another Month") { isCreatingMonth = true }
                        .accessibilityIdentifier("startAnotherMonthButton")
                }
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isCreatingMonth) {
                CreateMonthlyPlanView()
            }
        }
    }
}
