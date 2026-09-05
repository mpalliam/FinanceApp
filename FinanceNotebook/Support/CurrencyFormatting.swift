import Foundation

extension Decimal {

    /// Locale-aware currency text, e.g. "$14.72" or "$2,400.00" in en_US.
    ///
    /// The stored value stays a Decimal; this is presentation only.
    var currencyText: String {
        formatted(.currency(code: Self.currencyCode))
    }

    /// Currency text that always carries its sign, e.g. "+$100.00".
    ///
    /// Money Added reads as an addition rather than as a plain balance. The
    /// sign comes from the formatter, so it lands in the right place for the
    /// locale -- "+$100.00", never "$+100.00". Zero stays unsigned.
    var signedCurrencyText: String {
        formatted(.currency(code: Self.currencyCode).sign(strategy: .always(showZero: false)))
    }

    private static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
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
