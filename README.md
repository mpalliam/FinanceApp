# Finance Notebook

An iPhone app for tracking money you already have.

Finance Notebook is not an income manager and it does not connect to a bank.
The model it supports is deliberately small:

```
know how much money you have
 → decide how much to protect
 → create budgets
 → record expenses manually
 → understand where the money went
 → carry the remainder into next month
```

Entry is manual by design. Nothing is imported, so what is recorded is what was
meant to be recorded.

## What it does

- Monthly plans: starting money, protected money, category budgets
- Manual expense tracking with categories
- Money Added entries for money arriving mid-month
- Month creation, switching, rollover, and closing
- Cleanup tools for uncategorized spending, including bulk reassignment
- Weekly reviews and a monthly reflection
- Monthly reports, exportable as PDF
- Versioned JSON backup, and restore with validation

## What it deliberately does not do

No bank sync, no cloud sync, no accounts, no analytics, no telemetry, no
networking of any kind, and no third-party dependencies.

## Architecture

SwiftUI and SwiftData, no external packages.

```
FinanceNotebook/
  Models/       @Model types and the versioned schemas
  Services/     all business logic, static and testable
  Views/        SwiftUI screens, grouped by feature
  Support/      shared wording, document picker, DEBUG-only helpers
```

Money is `Decimal` throughout, never `Double`. Totals are derived rather than
stored, so a total cannot disagree with the records behind it. Business logic
lives in services so it can be tested without driving the UI. There are no
repositories, dependency-injection containers, or coordinators.

| | |
|---|---|
| Deployment target | iOS 17.0 |
| Devices | iPhone |
| Current schema | `FinanceNotebookSchemaV2` |
| Backup format | Version 1 |
| Storage | Local SwiftData store, CloudKit explicitly disabled |

Schema versioning and the V1 → V2 migration are described in
[Docs/SchemaVersioning.md](Docs/SchemaVersioning.md).

## Building and testing

```bash
# tests, run in six batches
./Scripts/run-tests.sh

# debug build
xcodebuild build -project FinanceNotebook.xcodeproj -scheme FinanceNotebook \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# release build for a device slice, without a signing identity
xcodebuild build -project FinanceNotebook.xcodeproj -scheme FinanceNotebook \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

The test suite is split into six batches on purpose. Running it in a single
invocation degrades the simulator part way through, after which tests that
normally take seconds start timing out while synthesizing events. The reasoning
is written up at the top of `Scripts/run-tests.sh`.

## Your data

Everything is stored locally on the device. Backups are plaintext JSON: they
contain full financial history and are not encrypted. Deleting the app deletes
the local store, so export a backup before deleting it or changing phones.

## Documentation

- [Docs/SchemaVersioning.md](Docs/SchemaVersioning.md) — schema versions and migration
- [Docs/Reporting.md](Docs/Reporting.md) — monthly reports and PDF rendering
- [Docs/BackupAndRestore.md](Docs/BackupAndRestore.md) — backup format and restore
- [Docs/ProductPolish.md](Docs/ProductPolish.md) — shared wording and cleanup tools
- [Docs/ReleaseReadiness.md](Docs/ReleaseReadiness.md) — versioning, signing, privacy, release checklist
- [Docs/V1Feedback.md](Docs/V1Feedback.md) — running log from real use
