import SwiftUI
import SwiftData

/// The month's check-ins and its end-of-month reflection.
///
/// Reviews are commentary, not ledger data, so this tab stays writable even
/// when the month is closed. Closing settles the money; it does not settle what
/// the user thinks about it.
struct ReviewView: View {

    let plan: MonthlyPlan

    @Environment(\.modelContext) private var context

    // Small collections, so fetching all and filtering in memory keeps the
    // views reactive without dynamic query plumbing.
    @Query private var allWeeklyReviews: [WeeklyReview]
    @Query private var allMonthlyReviews: [MonthlyReview]

    private var weeklyReviews: [WeeklyReview] {
        allWeeklyReviews
            .filter { $0.plan?.id == plan.id }
            .sorted { $0.weekStartDate > $1.weekStartDate }
    }

    private var monthlyReview: MonthlyReview? {
        allMonthlyReviews.first { $0.plan?.id == plan.id }
    }

    private var thisWeekStart: Date { ReviewService.weekStart(for: Date()) }

    private var thisWeeksReview: WeeklyReview? {
        weeklyReviews.first { $0.weekStartDate == thisWeekStart }
    }

    /// This week only belongs to this month when the month is the current one.
    /// Looking back at an old month should not offer to write "this week's"
    /// check-in into it.
    private var isViewingCurrentMonth: Bool {
        let calendar = Calendar.current
        return plan.month == calendar.component(.month, from: Date())
            && plan.year == calendar.component(.year, from: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                if weeklyReviews.isEmpty && monthlyReview == nil {
                    emptyState
                }

                monthlySection
                weeklySection
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MonthSelectorButton(plan: plan)
                }
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("No Reviews Yet").font(.headline)
                Text("Use weekly check-ins to keep your spending intentional, and the monthly reflection to look back on the month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("reviewEmptyState")
        }
    }

    // MARK: - Monthly

    private var monthlySection: some View {
        Section("THIS MONTH") {
            NavigationLink {
                MonthlyReflectionView(plan: plan)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Reflection")
                    Text(monthlyReview == nil ? "Not started" : "Written")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("monthlyReflectionLink")
        }
    }

    // MARK: - Weekly

    private var weeklySection: some View {
        Section("WEEKLY CHECK-INS") {
            ForEach(weeklyReviews) { review in
                NavigationLink {
                    WeeklyReviewView(plan: plan, weekStart: review.weekStartDate)
                } label: {
                    weeklyRow(review)
                }
                .accessibilityIdentifier("weeklyReview-\(Self.weekLabel(review.weekStartDate))")
            }

            if isViewingCurrentMonth {
                NavigationLink {
                    WeeklyReviewView(plan: plan, weekStart: thisWeekStart)
                } label: {
                    Text(thisWeeksReview == nil
                         ? "Start This Week's Review"
                         : "View This Week's Review")
                }
                .accessibilityIdentifier("thisWeeksReviewLink")
            } else if weeklyReviews.isEmpty {
                Text("No check-ins were written this month.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weeklyRow(_ review: WeeklyReview) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Week of \(Self.weekLabel(review.weekStartDate))")
            // A short preview only; the list is not the place to read it all.
            if let note = review.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func weekLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
