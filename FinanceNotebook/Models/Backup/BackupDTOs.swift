import Foundation

/// A complete, machine-readable copy of the notebook.
///
/// Deliberately not the SwiftData models. Encoding `@Model` types directly
/// would tie the file on disk to whatever the app's classes happen to look
/// like, so every future model change would silently change the backup format.
/// These plain structs are the format, and they change only when we decide to
/// change them.
///
/// Records are flat arrays with explicit UUID references rather than nested
/// under their plan. Nesting would make a dangling reference impossible to
/// *express*, which sounds safer but means a corrupt file could never be
/// caught -- there would be nothing to catch. Explicit ids give the validator
/// something real to check.
struct FinanceNotebookBackup: Codable, Equatable {

    /// The version of *this file format*, not of the app's database.
    ///
    /// The two move independently on purpose: the app may reach schema V4 and
    /// still read a format-1 backup, and the format may reach 2 without the
    /// database changing at all.
    let formatVersion: Int

    let exportedAt: Date

    /// Which database schema produced this file. Provenance only -- it is never
    /// used to decide how to decode, or the two versioning schemes would become
    /// entangled again.
    let sourceSchemaVersion: String

    var plans: [BackupPlan]
    var categories: [BackupCategory]
    var expenses: [BackupExpense]
    var moneyAdded: [BackupMoneyAddedEntry]
    var weeklyReviews: [BackupWeeklyReview]
    var monthlyReviews: [BackupMonthlyReview]

    /// The only format this app writes, and the newest it can read.
    static let currentFormatVersion = 1

    static let currentSchemaVersion = "2.0.0"
}

struct BackupPlan: Codable, Equatable {
    let id: UUID
    let month: Int
    let year: Int

    /// Stored rather than derived, so a corrupted key is something the
    /// validator can notice instead of something restore quietly papers over.
    let monthKey: String

    /// Decimal strings. See BackupCoding.
    let startingBalance: String
    let protectedAmount: String

    let isClosed: Bool
    let createdAt: Date
}

struct BackupCategory: Codable, Equatable {
    let id: UUID
    let planID: UUID
    let name: String
    let monthlyBudget: String

    /// "fixed" or "flexible" -- the raw value, never the label shown to a
    /// person, which is free to be reworded or translated.
    let type: String
}

struct BackupExpense: Codable, Equatable {
    let id: UUID
    let planID: UUID

    /// nil for an expense whose category was deleted. Restored as nil, not
    /// invented into some "Uncategorized" category.
    let categoryID: UUID?

    let amount: String
    let date: Date
    let merchant: String
    let note: String?
    let createdAt: Date
}

struct BackupMoneyAddedEntry: Codable, Equatable {
    let id: UUID
    let planID: UUID
    let amount: String
    let date: Date
    let source: String
    let note: String?
    let createdAt: Date
}

struct BackupWeeklyReview: Codable, Equatable {
    let id: UUID
    let planID: UUID
    let weekStartDate: Date
    let note: String?
    let createdAt: Date
    let updatedAt: Date
}

struct BackupMonthlyReview: Codable, Equatable {
    let id: UUID
    let planID: UUID
    let spentMoreThanExpected: String?
    let avoidablePurchase: String?
    let worthwhilePurchase: String?
    let changeNextMonth: String?
    let additionalNotes: String?
    let createdAt: Date
    let updatedAt: Date
}

/// What the user is shown before agreeing to overwrite anything: enough to
/// recognise the backup, and no more. A confirmation screen is not the place to
/// list somebody's transactions.
struct BackupPreview: Equatable {
    let exportedAt: Date
    let formatVersion: Int
    let planCount: Int
    let categoryCount: Int
    let expenseCount: Int
    let moneyAddedCount: Int
    let weeklyReviewCount: Int
    let monthlyReviewCount: Int
    let oldestMonthTitle: String?
    let newestMonthTitle: String?

    var isEmpty: Bool { planCount == 0 }
}

// MARK: - Coding

/// How values are written, kept in one place so the writer and the reader
/// cannot drift apart.
enum BackupCoding {

    /// Money is written as a decimal string -- "14.72", never 14.72.
    ///
    /// A JSON number is a Double the moment most parsers touch it, and this app
    /// has spent seven milestones keeping money out of binary floating point.
    /// `Decimal.description` is locale-independent, so the written form is
    /// always dot-separated.
    static func encode(_ amount: Decimal) -> String {
        "\(amount)"
    }

    /// Parsed against a fixed locale, so a device that writes decimals with a
    /// comma cannot misread its own backup.
    static func decodeDecimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// ISO 8601 with fractional seconds.
    ///
    /// Precision is milliseconds: anything finer is lost, which matters only
    /// for createdAt/updatedAt and is documented rather than hidden. Dates are
    /// never written in a locale-dependent form.
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Dates written and read at millisecond precision. Two dates are "the
    /// same" to a backup if they agree to within this.
    static let datePrecision: TimeInterval = 0.001

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = dateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Not an ISO 8601 date: \(string)"
                )
            }
            return date
        }
        return decoder
    }
}
