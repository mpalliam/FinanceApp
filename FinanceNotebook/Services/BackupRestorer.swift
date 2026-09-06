import Foundation
import SwiftData

/// Puts a validated backup into the store, replacing whatever is there.
///
/// Restore is the only operation in this app that can destroy someone's
/// records, so it is staged deliberately:
///
///   Phase 1  decode and validate -- a pure check over the file, with the live
///            store untouched. A bad backup is rejected here, which is why a
///            corrupt file can never cause a single database change.
///
///   Phase 2  build the whole graph in a throwaway in-memory container and
///            verify it there. This proves the backup is not merely well-formed
///            but actually constructible, before anything real is touched.
///
///   Phase 3  the live store: delete and insert in one ModelContext and commit
///            with a single save(). Nothing reaches disk until that save, so a
///            failure part-way through leaves the file exactly as it was.
///
/// Phase 2 exists because validation checks the file and this checks the
/// consequences of the file. Anything that would fail on insertion fails in a
/// container nobody will miss.
enum BackupRestorer {

    /// What ended up in the store, checked against the backup before success is
    /// reported.
    struct RestoreSummary: Equatable {
        let plans: Int
        let categories: Int
        let expenses: Int
        let moneyAdded: Int
        let weeklyReviews: Int
        let monthlyReviews: Int
    }

    // MARK: - Restoring

    /// Replaces everything in `context` with the backup.
    ///
    /// Destructive by design and by name -- the caller is expected to have
    /// asked first.
    @discardableResult
    static func restore(
        _ validated: BackupValidator.Validated,
        into context: ModelContext
    ) throws -> RestoreSummary {

        // Phase 2: prove it builds somewhere harmless first.
        try stage(validated.backup)

        // Phase 3: the live store. Nothing below reaches disk until the single
        // save() at the end.
        do {
            context.rollback()          // discard anything already pending
            try deleteEverything(in: context)
            try insert(validated.backup, into: context)
            try context.save()
        } catch {
            // Nothing was saved, so the store on disk never changed.
            context.rollback()
            throw BackupError.restoreFailed
        }

        let summary = try count(in: context)
        guard summary == expectedCounts(of: validated.backup) else {
            throw BackupError.restoreVerificationFailed
        }
        return summary
    }

    /// Builds the backup in a disposable in-memory store to prove it can be
    /// built at all. Throws before the live store is touched if it cannot.
    private static func stage(_ backup: FinanceNotebookBackup) throws {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: FinanceNotebookSchemaV2.self),
                migrationPlan: FinanceNotebookMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
        } catch {
            throw BackupError.restoreFailed
        }

        let context = ModelContext(container)
        do {
            try insert(backup, into: context)
            try context.save()
        } catch {
            throw BackupError.restoreFailed
        }

        guard try count(in: context) == expectedCounts(of: backup) else {
            throw BackupError.restoreVerificationFailed
        }
    }

    // MARK: - Building the graph

    /// Inserts the backup's records, parents before children, keeping lookup
    /// maps so relationships are resolved by id rather than by searching.
    ///
    /// Every id is preserved. A restored expense is the same expense it was
    /// before the backup, which is what makes a backup a copy rather than a
    /// re-typing.
    private static func insert(
        _ backup: FinanceNotebookBackup,
        into context: ModelContext
    ) throws {

        var planByID: [UUID: MonthlyPlan] = [:]
        var categoryByID: [UUID: BudgetCategory] = [:]

        for dto in backup.plans {
            guard let starting = BackupCoding.decodeDecimal(dto.startingBalance),
                  let protected = BackupCoding.decodeDecimal(dto.protectedAmount)
            else { throw BackupError.invalidDecimal(value: dto.startingBalance) }

            let plan = MonthlyPlan(
                month: dto.month, year: dto.year,
                startingBalance: starting, protectedAmount: protected
            )
            // The model mints a fresh id and timestamp in init; a restore is a
            // copy, not a new record, so both are put back.
            plan.id = dto.id
            plan.isClosed = dto.isClosed
            plan.createdAt = dto.createdAt

            context.insert(plan)
            planByID[dto.id] = plan
        }

        for dto in backup.categories {
            guard let plan = planByID[dto.planID] else {
                throw BackupError.missingPlanReference(id: dto.planID)
            }
            guard let type = CategoryType(rawValue: dto.type) else {
                throw BackupError.invalidCategoryType(value: dto.type)
            }
            guard let budget = BackupCoding.decodeDecimal(dto.monthlyBudget) else {
                throw BackupError.invalidDecimal(value: dto.monthlyBudget)
            }

            let category = BudgetCategory(
                name: dto.name, monthlyBudget: budget, type: type, plan: plan
            )
            category.id = dto.id
            context.insert(category)
            categoryByID[dto.id] = category
        }

        for dto in backup.expenses {
            guard let plan = planByID[dto.planID] else {
                throw BackupError.missingPlanReference(id: dto.planID)
            }
            guard let amount = BackupCoding.decodeDecimal(dto.amount) else {
                throw BackupError.invalidDecimal(value: dto.amount)
            }

            // nil stays nil: an expense whose category was deleted is restored
            // uncategorized, not given an invented one.
            var category: BudgetCategory?
            if let categoryID = dto.categoryID {
                guard let found = categoryByID[categoryID] else {
                    throw BackupError.missingCategoryReference(id: categoryID)
                }
                category = found
            }

            let expense = Expense(
                amount: amount, date: dto.date, merchant: dto.merchant,
                note: dto.note, category: category, plan: plan
            )
            expense.id = dto.id
            expense.createdAt = dto.createdAt
            context.insert(expense)
        }

        for dto in backup.moneyAdded {
            guard let plan = planByID[dto.planID] else {
                throw BackupError.missingPlanReference(id: dto.planID)
            }
            guard let amount = BackupCoding.decodeDecimal(dto.amount) else {
                throw BackupError.invalidDecimal(value: dto.amount)
            }

            let entry = MoneyAddedEntry(
                amount: amount, date: dto.date, source: dto.source,
                note: dto.note, plan: plan
            )
            entry.id = dto.id
            entry.createdAt = dto.createdAt
            context.insert(entry)
        }

        for dto in backup.weeklyReviews {
            guard let plan = planByID[dto.planID] else {
                throw BackupError.missingPlanReference(id: dto.planID)
            }
            let review = WeeklyReview(
                weekStartDate: dto.weekStartDate, note: dto.note, plan: plan
            )
            review.id = dto.id
            review.createdAt = dto.createdAt
            review.updatedAt = dto.updatedAt
            context.insert(review)
        }

        for dto in backup.monthlyReviews {
            guard let plan = planByID[dto.planID] else {
                throw BackupError.missingPlanReference(id: dto.planID)
            }
            let review = MonthlyReview(plan: plan)
            review.id = dto.id
            review.spentMoreThanExpected = dto.spentMoreThanExpected
            review.avoidablePurchase = dto.avoidablePurchase
            review.worthwhilePurchase = dto.worthwhilePurchase
            review.changeNextMonth = dto.changeNextMonth
            review.additionalNotes = dto.additionalNotes
            review.createdAt = dto.createdAt
            review.updatedAt = dto.updatedAt
            context.insert(review)
        }
    }

    /// Children before parents, so no cascade can invalidate a list still being
    /// walked. Nothing is saved here -- the caller commits once.
    static func deleteEverything(in context: ModelContext) throws {
        for review in try context.fetch(FetchDescriptor<WeeklyReview>()) {
            context.delete(review)
        }
        for review in try context.fetch(FetchDescriptor<MonthlyReview>()) {
            context.delete(review)
        }
        for expense in try context.fetch(FetchDescriptor<Expense>()) {
            context.delete(expense)
        }
        for entry in try context.fetch(FetchDescriptor<MoneyAddedEntry>()) {
            context.delete(entry)
        }
        for category in try context.fetch(FetchDescriptor<BudgetCategory>()) {
            context.delete(category)
        }
        for plan in try context.fetch(FetchDescriptor<MonthlyPlan>()) {
            context.delete(plan)
        }
    }

    // MARK: - Counting

    static func count(in context: ModelContext) throws -> RestoreSummary {
        RestoreSummary(
            plans: try context.fetchCount(FetchDescriptor<MonthlyPlan>()),
            categories: try context.fetchCount(FetchDescriptor<BudgetCategory>()),
            expenses: try context.fetchCount(FetchDescriptor<Expense>()),
            moneyAdded: try context.fetchCount(FetchDescriptor<MoneyAddedEntry>()),
            weeklyReviews: try context.fetchCount(FetchDescriptor<WeeklyReview>()),
            monthlyReviews: try context.fetchCount(FetchDescriptor<MonthlyReview>())
        )
    }

    static func expectedCounts(of backup: FinanceNotebookBackup) -> RestoreSummary {
        RestoreSummary(
            plans: backup.plans.count,
            categories: backup.categories.count,
            expenses: backup.expenses.count,
            moneyAdded: backup.moneyAdded.count,
            weeklyReviews: backup.weeklyReviews.count,
            monthlyReviews: backup.monthlyReviews.count
        )
    }
}
