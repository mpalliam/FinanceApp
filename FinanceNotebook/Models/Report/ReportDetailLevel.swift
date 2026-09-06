import Foundation

/// How much of the month a report shows.
///
/// Three fixed levels rather than a section picker: the point is to choose the
/// depth of the look back, not to assemble a document.
enum ReportDetailLevel: String, CaseIterable, Identifiable {

    /// The numbers only: where the money went and what is left.
    case summary

    /// The numbers, plus what came in and what the month was made of.
    case standard

    /// Everything, including every expense and every check-in.
    case full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .summary: "Summary"
        case .standard: "Standard"
        case .full: "Full"
        }
    }

    /// What appears on the page at this level. Kept here rather than scattered
    /// through the view and the renderer, so the screen and the PDF cannot
    /// disagree about what a "Standard" report is.
    var includesMoneyAdded: Bool {
        self != .summary
    }

    var includesReflection: Bool {
        self != .summary
    }

    var includesExpenseLedger: Bool {
        self == .full
    }

    var includesWeeklyReviews: Bool {
        self == .full
    }

    /// The subtitle printed under the month on the PDF.
    var reportTitle: String {
        switch self {
        case .summary: "Summary Report"
        case .standard: "Standard Report"
        case .full: "Full Report"
        }
    }
}
