# Backup and Restore

A backup is a complete, machine-readable copy of the notebook that this app can
read back. **A PDF report is not a backup** — see the bottom of this page.

## Backup Format V1

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-09-05T14:30:00.000Z",
  "sourceSchemaVersion": "2.0.0",
  "plans": [...],
  "categories": [...],
  "expenses": [...],
  "moneyAdded": [...],
  "weeklyReviews": [...],
  "monthlyReviews": [...]
}
```

### Format version is not the schema version

`formatVersion` describes **this file**. `sourceSchemaVersion` records which
database schema produced it, as provenance only — it never decides how the file
is decoded.

The two move independently on purpose. The app may one day reach schema V4 and
still read a format-1 backup; the format may reach 2 without the database
changing at all. Tying them together would mean every model change forced a new
file format, and every file-format change forced a migration.

**SwiftData migration** handles *old database → current database*.
**Backup compatibility** handles *old file → current app*. They never meet.

### DTOs

Plain `Codable` structs, never `@Model`. Encoding the SwiftData classes directly
would tie the file on disk to whatever those classes happen to look like, so
every future model change would silently change the backup format. These structs
*are* the format, and they change only when we decide to change them.

### Decimal encoding

Money is written as a **decimal string** — `"14.72"`, never `14.72`.

A JSON number becomes a `Double` the moment most parsers touch it, and this app
has spent seven milestones keeping money out of binary floating point.
`Decimal.description` is locale-independent, so the written form is always
dot-separated; reading parses against a fixed `en_US_POSIX` locale, so a device
that writes decimals with a comma cannot misread its own backup.

Verified end to end for `0.01`, `0.10`, `14.72`, `42.18`, `100.00`, `2400.00`
and `999999.99`, comparing `Decimal` values rather than formatted strings.

**The written form is normalised.** `Decimal.description` drops trailing zeros,
so `2400.00` is written as `"2400"` and a `200.00` budget as `"200"`. The
*value* is exact either way — `Decimal(string: "2400") == Decimal(string:
"2400.00")` — which is why the tests compare Decimals and not text. Do not
expect the file to preserve how many decimal places were typed.

### Date encoding

ISO 8601 with fractional seconds, UTC.

**Precision is milliseconds.** Anything finer is lost. That matters only for
`createdAt`/`updatedAt`, it is documented rather than hidden, and the round-trip
tests compare with a 1 ms tolerance rather than pretending exactness.

### Relationship encoding

Flat top-level arrays with **explicit UUID references** — `planID`,
`categoryID?` — rather than nesting children under their plan.

Nesting looks safer because a dangling reference becomes impossible to express.
That is exactly the problem: a corrupt file could then never be *caught*, since
there would be nothing to catch. Explicit ids give the validator something real
to check, which is what makes the corruption tests meaningful.

Relationships are never inferred from names. `"Groceries"` is not an identity.

**An uncategorized expense omits `categoryID` entirely** rather than writing
`null` — that is Swift's default for a nil optional. It decodes back to nil, and
the round trip is tested, but anyone reading the file by hand should expect an
absent key rather than an explicit null.

### UUIDs are preserved

A restored expense keeps the id it had before the backup. That is what makes a
backup a copy rather than a re-typing, and what makes round-trip comparison
possible at all.

## Export

Read-only. Making a copy of the notebook does not alter it — not a timestamp,
not a closed flag. Verified by capturing counts, timestamps and closed state
before and after.

Arrays are sorted deterministically (plans by year/month/id, categories by
name/id, expenses and money added by date/createdAt/id, reviews by date/id) so
two exports of an unchanged notebook produce **byte-identical files**. That makes
backups diffable and makes the round-trip tests mean something.

Filename: `Finance-Notebook-Backup-2026-09-05-1430.financebackup`. The time is
included so two backups made on one day do not overwrite each other.

## Validation

Everything checkable is checked **before the database is touched at all**. This
is a pure function over decoded values, so a bad file is rejected while the live
store is still untouched rather than discovered halfway through writing it.
SwiftData is never asked to find the problems — by the time it could, the damage
would be done.

- `formatVersion` supported, and > 0
- decodes as JSON of the right shape
- every id unique across every record type
- month within 1–12
- `monthKey` matches its own month and year
- no two plans for the same month
- starting balance ≥ 0, protected amount ≥ 0, budget ≥ 0
- every amount parses as a `Decimal`
- expense and money-added amounts > 0
- category type is one this version knows
- every `planID` resolves
- every `categoryID` resolves
- an expense's category belongs to the **same plan**
- at most one monthly reflection per plan
- no two weekly check-ins in the same normalised week for one plan

Nothing is silently repaired. An expense pointing at another month's category is
corruption; restoring it as uncategorized would hide that rather than report it.

## Restore

```
select file → decode → validate → preview → confirm → restore → verify → refresh
```

Only two modes: **restore into an empty notebook** and **Replace Existing Data**.
There is no merge. Merge semantics around month uniqueness, id collisions and
closed months are easy to get subtly wrong, and getting them wrong loses data.

### Atomicity

Three phases, in this order:

1. **Decode and validate.** A pure check over the file. The live store is not
   opened. This is why a corrupt backup causes *zero* database changes — restore
   is never reached.
2. **Stage.** The whole graph is built and verified in a throwaway **in-memory
   container**. This proves the backup is not merely well-formed but actually
   constructible, before anything real is touched.
3. **Replace.** On the live store: delete children-before-parents and insert,
   all in one `ModelContext`, committed by a **single `save()`**. Nothing
   reaches disk until that save, so a failure part-way through leaves the file
   exactly as it was. Any throw triggers `rollback()`.

`rollback()` recovering unsaved deletes is **tested directly**
(`testRollbackUndoesUnsavedDeletes`) rather than assumed. This project has
already been bitten by SwiftData deleting things quietly, and step 3's safety
rests entirely on that behaviour.

**Honest limit:** if the single `save()` itself fails at the storage layer, the
code rolls back and reports failure, but that specific failure has not been
forced in a test — there is no clean way to make SwiftData fail a save on
demand. What *is* proven is that every failure the app can detect happens in
phase 1 or 2, before the live store is written to.

### Verification before success

After the save, record counts for all six types are compared against the backup.
"Backup Restored" is shown only if they match; otherwise the restore reports
failure.

### After restore

The previously selected month may no longer exist. If the stored `monthKey` is
not among the restored months it is cleared, and `MonthSelection` falls back to
the current month, then the newest, then none. Settings dismisses on success so
no screen keeps holding an object from the replaced graph.

## What the user sees before overwriting

Counts and a date range — months, categories, expenses, money added, weekly
reviews, monthly reflections, oldest and newest month. **Never the records
themselves**: a confirmation screen is not the place to display somebody's
transactions.

If the device already holds data, the action reads **Replace Existing Data** and
requires a destructive confirmation that says plainly what will be removed and
that it cannot be undone without another backup. Cancelling changes nothing.

No automatic backup is taken before replacing. Doing so quietly would imply a
recovery guarantee the app has not actually made.

## Not implemented, deliberately

- **Merge restore** — too easy to get wrong, and wrong means data loss
- **Encryption** — badly designed crypto makes backups unrecoverable; correct,
  versioned, validated and restorable comes first
- **Automatic or scheduled backups** — restore correctness has to be proven
  before anything is automated
- **CSV** — cannot express the relational notebook

## A PDF is not a backup

Nothing in the app calls a PDF a backup or offers to restore from one. A PDF is
for a person to read; it cannot reconstruct the store. Implying otherwise is the
kind of promise only discovered to be false at the worst possible moment.

## Privacy

Everything stays on the device. The app uploads nothing and calls no APIs. The
share sheet and file importer let the *user* choose iCloud Drive, Files or
AirDrop — that is their choice, not the app's. Backup contents are never logged.

## Schema

Milestone 8 required **no schema change**. `FinanceNotebookSchemaV2` remains
current, V1 and the migration plan are untouched, and there is no V3.
