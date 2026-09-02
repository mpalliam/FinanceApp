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
| Current version | `FinanceNotebookSchemaV1`, `Schema.Version(1, 0, 0)` |
| Models | `MonthlyPlan`, `BudgetCategory`, `Expense`, `MoneyAddedEntry` |
| Stages | none yet -- V1 is the first version |

There is no V1 to V2 migration to test yet. `StoreRoundTripTests` proves the
versioned schema and plan can reopen a real on-disk store without losing data;
it does **not** prove cross-version migration, because no second version exists.
The first real schema change must bring its own migration test.
