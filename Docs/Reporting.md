# Monthly Reports

A report is a way of looking back at a month. It is not a new financial record,
and it is **not a backup** — see the bottom of this page.

## Detail levels

| | Summary | Standard | Full |
|---|---|---|---|
| Financial summary | ✓ | ✓ | ✓ |
| Categories (+ uncategorized) | ✓ | ✓ | ✓ |
| Money added | | ✓ | ✓ |
| Monthly reflection | | ✓ | ✓ |
| Expense ledger | | | ✓ |
| Weekly check-ins | | | ✓ |

Three fixed levels, not a section picker. The choice is how deep to look, not
which pieces to assemble, and every extra knob is another way for two people to
produce documents that cannot be compared.

`ReportDetailLevel` owns this table. The screen and the renderer both read it,
so they cannot disagree about what "Standard" means.

## Ordering

Everything in a report reads **oldest first** — a report is a ledger read
forward, which is the opposite of the app's screens, where the newest thing
matters most.

Ties are broken by `createdAt`, then by `id`. Both tie-breakers exist so the
ordering is *total*: the same month must always produce the same document, and
two records saved in the same second must not swap places between exports.

Categories are alphabetical for the same reason.

## Architecture

```
MonthlyPlan ──▶ MonthlyReportBuilder ──▶ MonthlyReportSnapshot ──┬──▶ MonthlyReportView
                        │                                        └──▶ MonthlyReportPDFRenderer
                        └── FinanceCalculator
```

`MonthlyReportSnapshot` is a plain struct — never a `@Model`. Nothing about a
report is persisted: no stored totals, no export history, no saved PDF paths.
It is rebuilt from the ledger every time it is asked for.

**The screen and the PDF render from the same snapshot.** This is the point of
the design. If each queried SwiftData and did its own arithmetic, they could
drift by a cent, and a report that disagrees with the app makes both
untrustworthy. All money arithmetic is delegated to `FinanceCalculator`; the
builder sorts and shapes, and computes nothing itself.

The renderer knows nothing about SwiftData. It takes a snapshot and returns
bytes, which is what makes it testable without a store or a screen.

## Read-only

Building or exporting a report performs no insert, update, delete or save.
Looking back at a month must not change it — and that has to hold for closed
months, which are exactly the ones most worth reporting on.

This is verified rather than assumed: `testBuildingAReportChangesNothing`
captures record counts and timestamps for all six model types, builds a report,
renders a Full PDF, and asserts nothing moved.

## PDF

- **`UIGraphicsPDFRenderer`**, Apple-native. No third-party library.
- **US Letter**, 8.5 × 11 inches (612 × 792 pt). Fixed, never derived from the
  device: a report printed from an iPad and one from an iPhone should be the
  same document.
- **0.75 inch margins**, so nothing is clipped by a printer.
- **System fonts only.**

### Pagination

A cursor walks down the page. Before each row it asks whether the row still
fits; if not, it breaks. Nothing is scaled to fit and nothing is clipped, so a
month with 200 expenses produces a longer document rather than a squashed one.

Section headings reserve room for a following row before committing, so a
heading cannot be stranded alone at the foot of a page.

Long text wraps, and spills onto further pages when it has to. A long monthly
reflection gets as many pages as it needs — the user's writing is not truncated
to make the layout easier.

### Page numbers

The footer says "Page 2 of 5", which means the total has to be known before the
first page is drawn. The renderer therefore lays the document out **twice**:
once to count pages via `CGPDFDocument`, then again with the total in hand.
Reports are small enough that the second pass costs nothing.

### Files

PDFs are written to the temporary directory under a deterministic name:

```
Finance-Notebook-2026-09-Full.pdf
```

The temporary directory, not app storage — a report is a document the user is
sending somewhere, not data the app keeps. Re-exporting the same month
overwrites the previous file rather than accumulating copies. The file stays on
disk while the share sheet is open, because `UIActivityViewController` reads it
lazily and deleting it early would hand the user an empty document.

## A PDF is not a backup

Nothing in the app calls this a backup or offers to restore from one. A PDF is
for a person to read; it cannot reconstruct the store, and implying otherwise
would be the kind of promise that is only discovered to be false at the worst
possible moment. Real backup and restore is a separate concern.

## Schema

Milestone 7 required **no schema change**. `FinanceNotebookSchemaV2` remains
current, V1 and the migration plan are untouched, and there is no V3.
