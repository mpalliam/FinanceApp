# Schema Versioning Rules

**Never modify a schema version that has already been used in place.**

This is not a style preference. It is the rule that keeps real financial
records from disappearing.

## What happened, and why this rule exists

During Milestone 1.1 the `Transaction` model was renamed to `Expense`. The app
had no versioned schema at the time, so SwiftData opened the store with
`NSMigratePersistentStoresAutomaticallyOption` and
`NSInferMappingModelAutomaticallyOption` both set. It inferred a mapping and
applied it:

- `ZTRANSACTION` was dropped and `ZEXPENSE` created
- **every row in every table was discarded**, including `MonthlyPlan` and
  `MoneyAddedEntry`, which had not been renamed but whose entity hashes changed
  along with their relationships
- **no error was raised, and the app launched normally**

That was harmless because the store held nothing but sample data. Repeated
against real records it is silent, total, unrecoverable data loss.

## The rule

Once a version exists, it is frozen. To change the model, add a new version and
a migration stage:

```
FinanceNotebookSchemaV1
        |
        v   MigrationStage
FinanceNotebookSchemaV2
```

Do not edit `FinanceNotebookSchemaV1` or the models it contains.

## Changes that require a new version

Any of these changes the store's shape and must go through a new version and a
stage:

- renaming a model
- renaming a persistent property
- adding, removing or re-pointing a relationship
- changing a delete rule
- changing a stored type (for example `Decimal` to `Double` -- don't)
- adding a non-optional property with no default
- removing a property
- adding, removing or changing an `@Attribute(.unique)` constraint

Adding an **optional** property, or one with a default, is usually a lightweight
migration -- but it still gets a version and a stage. "Usually lightweight" is
not a guarantee, and the point of the stage is that the decision is recorded
rather than inferred.

## How to add a version

1. Copy the models that actually change into `FinanceNotebookSchemaV2` as
   nested types. Models that are unchanged can keep being referenced from the
   top level.
2. Add `FinanceNotebookSchemaV2` to `FinanceNotebookMigrationPlan.schemas`,
   after V1.
3. Add a `MigrationStage` to `FinanceNotebookMigrationPlan.stages`. Use
   `.lightweight` only when the change genuinely needs no data rewriting;
   otherwise use `.custom` and do the work in `didMigrate`.
4. **Write a migration test before shipping it.** Build a store at V1, populate
   it with realistic data, migrate it, and assert every record and relationship
   survived with the right values. `StoreRoundTripTests` is the shape to copy.
5. Only then point the app at the new version.

## Why the V1 models are not nested

`FinanceNotebookSchemaV1` references its models at the top level instead of
nesting them. Nesting changes a type's Swift name, and SwiftData derives entity
identity from the type -- nesting them at the moment versioning was introduced
would have risked renaming every entity in the existing store, which is the
exact failure this infrastructure exists to prevent.

When V2 needs a genuinely different shape of a model, that model gets copied
into the version enum at that point, deliberately and with a stage and a test
covering it.

## Current state

| | |
|---|---|
| Current version | `FinanceNotebookSchemaV2`, `Schema.Version(2, 0, 0)` |
| Finance models | `MonthlyPlan`, `BudgetCategory`, `Expense`, `MoneyAddedEntry` |
| Review models | `WeeklyReview`, `MonthlyReview` |
| Stages | `V1 -> V2`, lightweight |

## V2: why it exists

Reviews needed somewhere durable to live. Weekly check-in notes and the monthly
reflection are the user's own words -- they cannot be recomputed, so they have
to be stored.

Nothing else changed. No finance model was renamed, reshaped, or given a new
stored property. V2 is V1 plus two entities.

### What is NOT stored on a review

No `totalSpent`, no `safeToSpend`, no category totals. The numbers a review
shows are recomputed from the ledger through `FinanceCalculator` every time it
opens, so a six-month-old reflection can never disagree with the records it was
written about. Only the prose is persisted.

## The thing that went wrong, and the rule it produced

The first attempt kept `FinanceNotebookSchemaV1` referencing the app's live
model types, exactly as Milestone 1.2 left it, and gave the reviews a
one-directional link: `WeeklyReview.plan` with no matching array on
`MonthlyPlan`. The intent was that `MonthlyPlan` would stay untouched and V1
would stay honest.

**SwiftData synthesises the inverse anyway.** `MonthlyPlan` gained the review
relationship whether or not it was declared, and because V1 pointed at that same
type, V1 silently acquired it too. V1 and V2 became the same schema and SwiftData
refused the whole plan at launch:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
    reason: 'Duplicate version checksums detected.'
```

The app crashed on start. Loudly, which is the good case -- the dangerous
version of this mistake is the one that migrates quietly and drops rows.

**Rule: a frozen schema version must own its models.** From V1 onward, each
`VersionedSchema` nests its own copies of the models it describes. Referencing
the live types works only until the live types change, and "the live types will
never change" is exactly the assumption a schema version exists to stop relying
on.

Nesting was verified not to rename entities: the migration test writes a V1
store with the nested types and reads `sqlite_master` directly, confirming the
tables are still `ZMONTHLYPLAN`, `ZEXPENSE` and so on.

`CategoryType` is deliberately still shared between versions. It is a Codable
enum, not an entity, so it plays no part in schema identity, and sharing it
guarantees both versions encode it identically.

## Migration type: lightweight, and why that is safe here

`MigrationStage.lightweight(fromVersion: V1, toVersion: V2)`.

Lightweight is correct **only** because the change is purely additive. Two new
entities appear; nothing existing is renamed, retyped, or re-related. Had
`MonthlyPlan` genuinely gained a relationship, this would have been a real data
change and would have needed a custom stage.

## What the migration test actually proves

`SchemaMigrationTests` writes a real store to disk using the V1 nested models,
confirms via `sqlite_master` that it contains no review tables, then reopens
that same file through `FinanceNotebookMigrationPlan` as V2 and checks:

- every `MonthlyPlan`, `BudgetCategory`, `Expense` and `MoneyAddedEntry` id
- `month`, `year`, `monthKey`, `startingBalance`, `protectedAmount`
- `isClosed` on a month that was closed before migrating
- `Expense -> BudgetCategory` and `Expense -> MonthlyPlan`
- `MoneyAddedEntry -> MonthlyPlan`
- an expense whose category was deleted stays uncategorized
- `0.01`, `14.72`, `42.18`, `100.00`, `2400.00` exactly
- that no review records were invented
- that closed-month write protection still refuses writes afterwards
- that the migrated store then accepts new reviews which persist across a reopen
- that migrating an already-migrated store changes nothing

A fresh V2 store is tested separately, so success does not depend on having
migrated.

**What it does not prove:** V2 -> V3. Every future version brings its own test.

## Adding V3

1. Nest the models V3 needs into `FinanceNotebookSchemaV3`. Do not reference the
   live types, and do not edit V1 or V2.
2. Append it to `FinanceNotebookMigrationPlan.schemas`.
3. Add a `MigrationStage`. Use `.lightweight` only for genuinely additive
   changes; anything that moves data needs `.custom` and a `didMigrate` that
   does the moving.
4. Write the migration test before shipping it. Copy the shape of
   `SchemaMigrationTests`: build a real V2 store, migrate it, assert every id,
   relationship, flag and Decimal.
5. Only then point the app at the new version.
