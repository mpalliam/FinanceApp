import Foundation
import UIKit

enum ReportRenderError: Error, LocalizedError {
    case couldNotWriteFile

    var errorDescription: String? {
        switch self {
        case .couldNotWriteFile: "The report could not be saved to share."
        }
    }
}

/// Draws a report snapshot as a PDF.
///
/// Knows nothing about SwiftData -- it takes a snapshot and produces bytes,
/// which is what makes it testable without a store or a screen.
///
/// US Letter, because the app is being used in the US. The size is fixed rather
/// than derived from the device: a report printed from an iPad and one printed
/// from an iPhone should be the same document.
enum MonthlyReportPDFRenderer {

    // 72 points to the inch.
    private static let pageSize = CGSize(width: 8.5 * 72, height: 11 * 72)
    private static let margin: CGFloat = 54          // 0.75"
    private static let footerHeight: CGFloat = 30

    // MARK: - Entry points

    /// Renders the report, laying it out twice: once to learn the page count,
    /// then again so the footer can say "Page 2 of 5" rather than just "Page 2".
    /// Reports are small enough that a second pass costs nothing.
    static func render(report: MonthlyReportSnapshot, level: ReportDetailLevel) -> Data {
        let firstPass = draw(report: report, level: level, totalPages: nil)
        let pageCount = pageCount(of: firstPass)
        return draw(report: report, level: level, totalPages: pageCount)
    }

    /// Writes the PDF where the share sheet can reach it.
    ///
    /// The temporary directory, not app storage: a report is a document the user
    /// is sending somewhere, not data the app keeps. Re-exporting the same month
    /// overwrites the previous file rather than piling up copies.
    @discardableResult
    static func write(
        report: MonthlyReportSnapshot,
        level: ReportDetailLevel,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let data = render(report: report, level: level)
        let url = directory.appending(path: fileName(for: report, level: level))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ReportRenderError.couldNotWriteFile
        }
        return url
    }

    /// e.g. "Finance-Notebook-2026-09-Full.pdf"
    static func fileName(for report: MonthlyReportSnapshot, level: ReportDetailLevel) -> String {
        let key = String(format: "%04d-%02d", report.year, report.month)
        return "Finance-Notebook-\(key)-\(level.displayName).pdf"
    }

    static func pageCount(of data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }

    // MARK: - Drawing

    private static func draw(
        report: MonthlyReportSnapshot,
        level: ReportDetailLevel,
        totalPages: Int?
    ) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        return renderer.pdfData { context in
            let layout = Layout(
                context: context,
                pageSize: pageSize,
                margin: margin,
                footerHeight: footerHeight,
                totalPages: totalPages
            )
            layout.beginPage()

            drawHeader(report: report, level: level, in: layout)
            drawFinancialSummary(report, in: layout)
            drawCategories(report, in: layout)

            if level.includesMoneyAdded {
                drawMoneyAdded(report, in: layout)
            }
            if level.includesExpenseLedger {
                drawExpenses(report, in: layout)
            }
            if level.includesWeeklyReviews {
                drawWeeklyReviews(report, in: layout)
            }
            if level.includesReflection {
                drawReflection(report, in: layout)
            }

            layout.finishPage()
        }
    }

    // MARK: - Sections

    private static func drawHeader(
        report: MonthlyReportSnapshot,
        level: ReportDetailLevel,
        in layout: Layout
    ) {
        // Letter-spacing beyond about this much makes text extract with gaps
        // between the characters, which quietly costs the PDF its searchability
        // and its accessibility. The spacing is worth less than that.
        layout.text("FINANCE NOTEBOOK", font: .systemFont(ofSize: 11, weight: .semibold),
                    color: .secondaryLabel, tracking: 1.2)
        layout.space(6)
        layout.text(report.monthTitle, font: .systemFont(ofSize: 26, weight: .bold))
        layout.space(2)
        layout.text(level.reportTitle, font: .systemFont(ofSize: 13), color: .secondaryLabel)

        // Say plainly whether the month was finished, so nobody mistakes a
        // mid-month snapshot for a final one.
        layout.space(2)
        layout.text(
            report.isClosed
                ? FinanceCopy.closedMonthNotice
                : "Generated while the month was still open.",
            font: .systemFont(ofSize: 10),
            color: .secondaryLabel
        )
        layout.space(14)
        layout.rule()
        layout.space(14)
    }

    private static func drawFinancialSummary(_ report: MonthlyReportSnapshot, in layout: Layout) {
        layout.heading("FINANCIAL SUMMARY")
        let summary = report.summary
        layout.row("Starting Money", summary.startingBalance.currencyText)
        layout.row("Money Added", report.moneyAdded.isEmpty
                   ? summary.moneyAdded.currencyText
                   : summary.moneyAdded.signedCurrencyText)
        layout.row("Total Money", summary.totalMoney.currencyText, emphasised: true)
        layout.space(6)
        layout.row("Total Spent", summary.totalSpent.currencyText)
        layout.row("Money Remaining", summary.moneyRemaining.currencyText, emphasised: true)
        layout.space(6)
        layout.row("Protected Money", summary.protectedAmount.currencyText)
        layout.row("Safe to Spend", summary.safeToSpend.currencyText, emphasised: true)
        layout.space(16)
    }

    private static func drawCategories(_ report: MonthlyReportSnapshot, in layout: Layout) {
        layout.heading("CATEGORIES")

        if report.categories.isEmpty {
            layout.text("No categories this month.", font: .systemFont(ofSize: 11),
                        color: .secondaryLabel)
            layout.space(6)
        }

        for category in report.categories {
            layout.row("\(category.name)  (\(category.typeName))",
                       "\(category.spent.currencyText) of \(category.budget.currencyText)")
            layout.detail(statusText(for: category))
            layout.space(4)
        }

        // Spending whose category was deleted. It has no budget, and inventing
        // one would misrepresent the month.
        if let uncategorized = report.uncategorized {
            layout.space(4)
            layout.row("Uncategorized", uncategorized.spent.currencyText)
            layout.detail("\(uncategorized.expenseCount) "
                          + (uncategorized.expenseCount == 1 ? "expense" : "expenses")
                          + " with no category")
        }
        layout.space(16)
    }

    private static func statusText(for category: MonthlyReportSnapshot.CategoryRow) -> String {
        FinanceCopy.budgetStatus(spent: category.spent, budget: category.budget)
    }

    private static func drawMoneyAdded(_ report: MonthlyReportSnapshot, in layout: Layout) {
        layout.heading("MONEY ADDED")

        if report.moneyAdded.isEmpty {
            layout.text("No money added this month.", font: .systemFont(ofSize: 11),
                        color: .secondaryLabel)
            layout.space(16)
            return
        }

        for entry in report.moneyAdded {
            layout.row("\(shortDate(entry.date))   \(entry.source)",
                       entry.amount.signedCurrencyText)
            if let note = entry.note, !note.isEmpty {
                layout.detail(note)
            }
            layout.space(3)
        }
        layout.space(13)
    }

    private static func drawExpenses(_ report: MonthlyReportSnapshot, in layout: Layout) {
        layout.heading("EXPENSES")

        if report.expenses.isEmpty {
            layout.text("No expenses this month.", font: .systemFont(ofSize: 11),
                        color: .secondaryLabel)
            layout.space(16)
            return
        }

        for expense in report.expenses {
            layout.row("\(shortDate(expense.date))   \(expense.merchant)",
                       "-\(expense.amount.currencyText)")
            layout.detail(expense.categoryName)
            if let note = expense.note, !note.isEmpty {
                layout.detail(note)
            }
            layout.space(3)
        }
        layout.space(13)
    }

    private static func drawWeeklyReviews(_ report: MonthlyReportSnapshot, in layout: Layout) {
        layout.heading("WEEKLY CHECK-INS")

        if report.weeklyReviews.isEmpty {
            layout.text("No weekly check-ins recorded.", font: .systemFont(ofSize: 11),
                        color: .secondaryLabel)
            layout.space(16)
            return
        }

        for review in report.weeklyReviews {
            layout.text("Week of \(longDate(review.weekStartDate))",
                        font: .systemFont(ofSize: 11, weight: .semibold))
            layout.space(2)
            layout.text(review.note ?? "No note.", font: .systemFont(ofSize: 11),
                        color: review.note == nil ? .secondaryLabel : .label)
            layout.space(10)
        }
        layout.space(6)
    }

    private static func drawReflection(_ report: MonthlyReportSnapshot, in layout: Layout) {
        layout.heading("MONTHLY REFLECTION")

        guard let reflection = report.reflection, !reflection.isEmpty else {
            layout.text("No monthly reflection recorded.", font: .systemFont(ofSize: 11),
                        color: .secondaryLabel)
            layout.space(16)
            return
        }

        for answer in reflection.answers {
            layout.text(answer.question, font: .systemFont(ofSize: 11, weight: .semibold))
            layout.space(2)
            // Wraps, and spills onto another page if the answer is long. Nothing
            // the user wrote is cut short to make the layout easier.
            layout.text(answer.answer, font: .systemFont(ofSize: 11))
            layout.space(10)
        }
        layout.space(6)
    }

    // MARK: - Dates

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func longDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Layout

extension MonthlyReportPDFRenderer {

    /// A cursor down the page that starts a new one when it runs out of room.
    ///
    /// Deliberately simple: draw top to bottom, ask before each piece whether it
    /// fits, and break if it does not. Nothing is scaled down and nothing is
    /// clipped, so a month with two hundred expenses produces a longer document
    /// rather than a squashed one.
    final class Layout {

        private let context: UIGraphicsPDFRendererContext
        private let pageSize: CGSize
        private let margin: CGFloat
        private let footerHeight: CGFloat
        private let totalPages: Int?

        private var y: CGFloat = 0
        private(set) var pageNumber = 0
        private var isPageOpen = false

        private var contentWidth: CGFloat { pageSize.width - margin * 2 }
        private var bottomLimit: CGFloat { pageSize.height - margin - footerHeight }

        init(
            context: UIGraphicsPDFRendererContext,
            pageSize: CGSize,
            margin: CGFloat,
            footerHeight: CGFloat,
            totalPages: Int?
        ) {
            self.context = context
            self.pageSize = pageSize
            self.margin = margin
            self.footerHeight = footerHeight
            self.totalPages = totalPages
        }

        // MARK: Pages

        func beginPage() {
            context.beginPage()
            isPageOpen = true
            pageNumber += 1
            y = margin
        }

        func finishPage() {
            guard isPageOpen else { return }
            drawFooter()
            isPageOpen = false
        }

        /// Breaks to a new page unless `height` still fits.
        private func ensureSpace(_ height: CGFloat) {
            guard y + height > bottomLimit else { return }
            finishPage()
            beginPage()
        }

        private func drawFooter() {
            let label = totalPages.map { "Page \(pageNumber) of \($0)" } ?? "Page \(pageNumber)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(
                at: CGPoint(
                    x: (pageSize.width - size.width) / 2,
                    y: pageSize.height - margin - size.height
                ),
                withAttributes: attributes
            )
        }

        // MARK: Pieces

        /// A section heading, which refuses to be the last thing on a page.
        /// Stranding a heading above a page break looks like a mistake, so it
        /// reserves room for a row beneath it before committing.
        func heading(_ title: String) {
            ensureSpace(34 + 18)
            text(title, font: .systemFont(ofSize: 11, weight: .semibold),
                 color: .secondaryLabel, tracking: 1.2)
            space(3)
            rule()
            space(8)
        }

        /// A label on the left and a value on the right, both on one line.
        func row(_ label: String, _ value: String, emphasised: Bool = false) {
            let font = UIFont.systemFont(ofSize: 11, weight: emphasised ? .semibold : .regular)
            let valueFont = UIFont.monospacedDigitSystemFont(
                ofSize: 11, weight: emphasised ? .semibold : .regular
            )

            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: valueFont, .foregroundColor: UIColor.label
            ]
            let valueSize = (value as NSString).size(withAttributes: valueAttributes)

            // The label wraps if it is long, so the value never overlaps it.
            let labelWidth = contentWidth - valueSize.width - 12
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor.label
            ]
            let labelHeight = height(of: label, attributes: labelAttributes, width: labelWidth)
            let lineHeight = max(labelHeight, valueSize.height)

            ensureSpace(lineHeight + 2)

            (label as NSString).draw(
                with: CGRect(x: margin, y: y, width: labelWidth, height: labelHeight),
                options: [.usesLineFragmentOrigin], attributes: labelAttributes, context: nil
            )
            (value as NSString).draw(
                at: CGPoint(x: pageSize.width - margin - valueSize.width, y: y),
                withAttributes: valueAttributes
            )

            y += lineHeight + 2
        }

        /// A smaller line under a row: a category name, a note.
        func detail(_ string: String) {
            text(string, font: .systemFont(ofSize: 10), color: .secondaryLabel, indent: 0)
        }

        /// Wrapped text that flows onto further pages when it has to.
        ///
        /// A long reflection is the user's writing; it gets as many pages as it
        /// needs rather than being cut to fit.
        func text(
            _ string: String,
            font: UIFont,
            color: UIColor = .label,
            indent: CGFloat = 0,
            tracking: CGFloat = 0
        ) {
            guard !string.isEmpty else { return }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color
            ]
            if tracking != 0 { attributes[.kern] = tracking }

            let width = contentWidth - indent
            var remaining = Substring(string)

            while !remaining.isEmpty {
                let full = String(remaining)
                let fullHeight = height(of: full, attributes: attributes, width: width)

                if y + fullHeight <= bottomLimit {
                    (full as NSString).draw(
                        with: CGRect(x: margin + indent, y: y, width: width, height: fullHeight),
                        options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
                    )
                    y += fullHeight
                    return
                }

                // Not all of it fits. Take as much as will, break the page, and
                // carry the rest over.
                let available = bottomLimit - y
                if available < font.lineHeight * 1.5 {
                    finishPage()
                    beginPage()
                    continue
                }

                let split = splitIndex(
                    of: remaining, attributes: attributes,
                    width: width, maxHeight: available
                )
                guard split > remaining.startIndex else {
                    finishPage()
                    beginPage()
                    continue
                }

                let head = String(remaining[remaining.startIndex..<split])
                let headHeight = height(of: head, attributes: attributes, width: width)
                (head as NSString).draw(
                    with: CGRect(x: margin + indent, y: y, width: width, height: headHeight),
                    options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
                )

                remaining = remaining[split...].drop(while: { $0 == " " || $0 == "\n" })
                finishPage()
                beginPage()
            }
        }

        func space(_ points: CGFloat) {
            y += points
        }

        func rule() {
            ensureSpace(1)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
            UIColor.separator.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            y += 1
        }

        // MARK: Measuring

        private func height(
            of string: String,
            attributes: [NSAttributedString.Key: Any],
            width: CGFloat
        ) -> CGFloat {
            guard !string.isEmpty, width > 0 else { return 0 }
            let bounds = (string as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
            )
            return ceil(bounds.height)
        }

        /// The largest prefix of `text` that fits in `maxHeight`, found by
        /// walking back word by word. Words are kept whole.
        private func splitIndex(
            of text: Substring,
            attributes: [NSAttributedString.Key: Any],
            width: CGFloat,
            maxHeight: CGFloat
        ) -> Substring.Index {
            var candidate = text.startIndex
            var index = text.startIndex

            while index < text.endIndex {
                guard let nextBreak = text[index...].firstIndex(where: { $0 == " " || $0 == "\n" })
                else {
                    let whole = String(text)
                    if height(of: whole, attributes: attributes, width: width) <= maxHeight {
                        candidate = text.endIndex
                    }
                    break
                }

                let piece = String(text[text.startIndex..<nextBreak])
                if height(of: piece, attributes: attributes, width: width) <= maxHeight {
                    candidate = nextBreak
                    index = text.index(after: nextBreak)
                } else {
                    break
                }
            }
            return candidate
        }
    }
}
