# App Store Listing — Draft

Draft only. Nothing here has been submitted, and nothing should be submitted
without the developer's approval.

## Name

```
Finance Notebook
```

## Subtitle

```
A manual monthly money notebook
```

(30 characters, within Apple's limit.)

## Category

Primary: **Finance**

No secondary category. The alternative would be Productivity, which describes
the interaction style rather than the subject, and would compete for a less
relevant audience.

## Description

```
Finance Notebook helps you plan and track the money you already have.

Set your starting money, protect an amount you don't want to spend, create
category budgets, record expenses manually, add money when it arrives, and
review the month at your own pace.

Finance Notebook is manual by design. Nothing is imported from a bank, so what
you record is what you meant to record — and writing an expense down is what
makes you notice it.

FEATURES

• Monthly planning — starting money, protected money, and what's safe to spend
• Category budgets you set yourself
• Manual expense tracking
• Money Added entries for money that arrives mid-month
• A cleanup screen for spending you haven't categorised yet
• Weekly check-ins and a monthly reflection
• Monthly reports you can export as a PDF
• Backup and restore, so your notebook can move with you

YOUR DATA

Your financial data is stored on your iPhone. Finance Notebook has no account,
does not connect to your bank, and does not send your financial history
anywhere. Backups are files you create and put where you choose.

No bank connection is required. No account is required.
```

## Keywords

```
budget,expense,spending,money,tracker,manual,monthly,notebook,ledger,offline
```

Deliberately avoids "bank", "sync", "automatic", and "AI": none apply.

## Promotional text

```
Plan the month, write down what you spend, and see where it went. No bank
connection, no account, no sync.
```

## Privacy nutrition label

Expected answer: **Data Not Collected**.

Reasoning, to be re-checked against Apple's current definitions at submission:

- Apple's definition of *collection* is transmitting data off the device in a
  way that makes it available to the developer or a third party.
- The app performs no networking at all: there is no `URLSession`, no analytics,
  no crash reporter, and no third-party SDK.
- Financial data stays in the app's local store. It leaves only when the user
  exports a backup or a PDF and chooses a destination themselves. The developer
  never receives it, and an export the user initiates and directs is not
  developer collection.
- CloudKit is explicitly disabled, so nothing syncs to iCloud.
- There is no account, and no identifier is generated or stored.

The required-reason API declaration (`UserDefaults`, `CA92.1`) is separate from
the nutrition label and is declared in `FinanceNotebook/PrivacyInfo.xcprivacy`.

## Age rating

Expected **4+**. There is no objectionable content, no user-generated content
that is shared, no web view, no purchases, and no social features. The exact
answers depend on the App Store Connect questionnaire as presented at
submission; this is the expected outcome, not a filled-in form.

## Support and marketing URLs

A support URL is **required** by App Store Connect. None exists yet — see
`Docs/AppStore/Support.md` for the content to host. A marketing URL is optional
and is not planned for 1.0.

A privacy policy URL is required for App Store distribution. Draft text is in
`Docs/AppStore/PrivacyPolicy.md`. No URL has been invented.

## Claims that must never appear

Not true of this app, in any wording:

- secure banking, bank-level security, encrypted vault
- encrypted backups
- AI budgeting or financial advice
- automatic spending tracking or bank sync
- guaranteed savings

## Release notes — 1.0

```
Finance Notebook 1.0

A simple manual system for planning, tracking and reviewing your monthly money.

• Monthly money planning, with protected money and safe-to-spend
• Category budgets
• Manual expense tracking and Money Added entries
• Weekly check-ins and monthly reflections
• Monthly PDF reports
• Backup and restore

Your data stays on your iPhone.
```

## Screenshots

Generated from the fictional showcase dataset by the `ShowcaseCapture` UI test,
so they come from a real build rather than a mockup:

```bash
xcodebuild test-without-building \
  -project FinanceNotebook.xcodeproj -scheme FinanceNotebook \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FinanceNotebookUITests/ShowcaseCapture
```

The dataset is fictional and internally consistent — September 2026, starting
2,400, protected 1,000, added 100, spent 624, safe to spend 876 — with invented
merchants and no personal notes. No real financial data is ever used for store
screenshots.

Apple requires 6.9" screenshots; a 6.5" set may also be needed depending on the
current requirements at submission.
