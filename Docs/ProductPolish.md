# Product Conventions

What the app has settled on, so future work does not quietly diverge from it.

## Uncategorized cleanup

Deleting a category keeps its spending rather than destroying it — that rule has
been in place since Milestone 1 and is not negotiable. The consequence is that
the expenses are left with no category, sitting outside every budget.

Reassigning them one at a time through the edit screen worked, but was tedious
enough that it would not actually get done. **Plan → Uncategorized Spending** is
the fix: select any number of expenses, pick a category, done.

The section only appears when there is something to clean up. A month where
everything is categorised is not nagged about it.

### What bulk reassignment guarantees

Only `category` changes. Amount, date, merchant, note, month and — importantly —
the expense's **id** are untouched, so this files money differently rather than
rewriting it. It follows that **the month's totals cannot move**: `totalSpent`,
`moneyRemaining` and `safeToSpend` are identical before and after. Only the
split between categories changes.

Everything is validated before anything is written, and the whole set commits
with a **single save**, so a rejected reassignment leaves every expense exactly
as it was rather than changing some of them.

Refused, at the service layer rather than only in the UI:

- a **closed month** — tidying is still a financial change
- a **category from another month** — September's spending must never be filed
  under an October budget
- a **selection spanning two months** — rejected whole, never partly applied

An empty selection is a clean no-op returning 0, not an error. Nothing was asked
for, so nothing happens. The button is disabled at zero selection anyway.

## Closed months

One sentence, everywhere: **"This month is closed and can no longer be edited."**
It lives in `FinanceCopy.closedMonthNotice` because it was previously written
out separately on each screen and had already started to drift.

The rule is: **hide the action and explain why**, rather than leaving a disabled
control the user has to poke at to understand. Applied consistently across Home,
Transactions, Plan, Money Added, category edits and Uncategorized cleanup.

Reviews, reflections and reports stay available. Closing settles the money, not
what the user thinks about it.

The close confirmation says what will be lost *and* what survives, and does not
mention reopening — because reopening is not supported. A mistaken close remains
a known limitation.

## Naming

User-facing wording is fixed, even where the model differs:

| Shown | Model |
|---|---|
| Starting Money | `startingBalance` |
| Protected Money | `protectedAmount` |
| Money Added | `MoneyAddedEntry` |
| Money Remaining | derived |
| Safe to Spend | derived |
| Uncategorized | `category == nil` |

**Money Added is never called Income.** It covers refunds, reimbursements, money
from family and things sold — none of which recur, and calling it income would
misdescribe the product.

Persistent property names are not renamed to match. A rename is a schema change,
and this project has already watched one destroy a store.

## Shared copy

`FinanceCopy` holds only wording that more than one screen must agree on: the
closed-month sentence, the budget status line, the close-month warning, the
category deletion warning.

The budget status line previously existed in three files — Plan, the report
screen and the PDF renderer — each free to drift. It is one function now.

This is a handful of shared strings, deliberately not a localisation layer or a
design system.

## Money and dates

Money always goes through `Decimal.currencyText` or `.signedCurrencyText`. Never
a hand-built string. Expenses read negative and Money Added reads positive as a
matter of presentation only; the stored values are positive throughout.

Negative Safe to Spend is shown as it is. It is never clamped to zero and never
accompanied by a judgement — the number is the point.

## Deliberately deferred

Reopening a closed month · merge restore · backup encryption · automatic backups
· CSV · charts · annual reports · notifications · widgets · cloud or bank sync.

Each was considered and left out. Where one is a real limitation — a mistaken
close cannot be undone — it is recorded as such rather than quietly hoped over.
