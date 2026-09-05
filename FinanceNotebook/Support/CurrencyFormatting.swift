import Foundation

extension Decimal {

    /// Locale-aware currency text, e.g. "$14.72" or "$2,400.00" in en_US.
    ///
    /// The stored value stays a Decimal; this is presentation only.
    var currencyText: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

extension Date {

    /// "Today", "Yesterday", or a readable date for anything older.
    var expenseSectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
