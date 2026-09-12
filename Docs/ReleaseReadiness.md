# Release Readiness

How Finance Notebook 1.0 is built, signed, versioned and shipped.

## Production identity

| | |
|---|---|
| Display name | Finance Notebook |
| Product name (internal) | FinanceNotebook |
| Bundle identifier | `com.mathewabraham.FinanceNotebook` |
| Marketing version | 1.0 |
| Build | 1 |
| Deployment target | iOS 17.0 |
| Device family | iPhone |

The internal target is still `FinanceNotebook` with no space. That is
deliberate: renaming a target risks breaking scheme and test references for no
user-visible gain. `CFBundleDisplayName` carries the user-facing name instead.

Settings reads the version and build from `CFBundleShortVersionString` and
`CFBundleVersion`, so it cannot drift from the project.

## Version and build policy

Marketing version stays `1.0` until something user-facing changes. The build
number increases by one on every upload to App Store Connect:

```
1.0 (1)   first TestFlight build
1.0 (2)   next upload, same released feature set
1.1 (n)   when the product changes for users
```

Two builds may never share a build number under the same marketing version.
There is no CI versioning; bump `CURRENT_PROJECT_VERSION` in the project before
archiving.

## Build commands

Debug, simulator:

```bash
xcodebuild build \
  -project FinanceNotebook.xcodeproj \
  -scheme FinanceNotebook \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Release, device slice. `CODE_SIGNING_ALLOWED=NO` compiles the release
configuration without a signing identity, which is how the release build is
verified on a machine with no developer account:

```bash
xcodebuild build \
  -project FinanceNotebook.xcodeproj \
  -scheme FinanceNotebook \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Tests, six batches (see `Scripts/run-tests.sh` for why it is split):

```bash
./Scripts/run-tests.sh
```

## Signing and archive

The project uses automatic signing with no `DEVELOPMENT_TEAM` set. Before the
first real device build or archive:

1. Xcode → Settings → Accounts → add the Apple ID with the developer membership.
2. Select the `FinanceNotebook` target → Signing & Capabilities → pick the team.
   This writes `DEVELOPMENT_TEAM` into the project.
3. Connect the iPhone and run once to create a development provisioning profile.

Archive:

```
Product → Destination → Any iOS Device (arm64)
Product → Archive
```

Then Organizer → Validate App, and Distribute App → App Store Connect →
Upload.

Nothing about signing certificates or profiles belongs in this repository.

## TestFlight

Internal testing only for 1.0. The tester is the developer, and the goal is
daily personal use rather than broad feedback.

Prerequisites, all external to this repository:

- Apple Developer Program membership (paid)
- App Store Connect app record for `com.mathewabraham.FinanceNotebook`
- Current agreements accepted in App Store Connect
- A signing identity and provisioning profile on the build machine

Testing notes for the first build:

> Finance Notebook is a manual personal finance tracker.
>
> Please test: monthly setup, expenses, Money Added, budget categories,
> weekly and monthly reviews, PDF reports, and backup/restore.
>
> All financial data stays on the device unless you export it yourself.

## Privacy assumptions

These are claims the implementation actually supports. Do not widen them.

- **Storage.** SwiftData store in the app container. No CloudKit: the container
  is created with `cloudKitDatabase: .none`.
- **Network.** None. There is no `URLSession`, no API client, no analytics, no
  crash reporter, and no background networking anywhere in the app target.
- **Third-party SDKs.** None. The project has no package references.
- **Accounts.** None. There is no sign-in, and no user identifier is generated.
- **Privacy manifest.** `FinanceNotebook/PrivacyInfo.xcprivacy` declares no
  tracking and no collected data, and declares one required-reason API:
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, for
  `MonthSelection` remembering the selected month in the app's own defaults.
  No other required-reason API is used: no file-timestamp, disk-space,
  boot-time, or active-keyboard calls.
- **Backups are plaintext JSON.** They are not encrypted and must not be
  described as encrypted. Settings says so, once.
- **App Privacy questionnaire.** Expected answer is *Data Not Collected*:
  nothing leaves the device except through an export the user performs and
  directs. Re-check against Apple's current definitions at submission time.

## Backup file type

Backups are written as JSON with a `.financebackup` extension. The app declares
no custom `UTType`. The extension is therefore treated as generic data, and the
importer accepts `[.json, .data]`, so a backup opens whether or not Files
recognises the extension — including one renamed along the way. A custom
exported type would buy a nicer Files icon and nothing else, so it is
deliberately not declared.

## Debug/production separation

`DevelopmentSupport.swift` is wrapped in `#if DEBUG` from its first line to its
last, and its only call site in `FinanceNotebookApp.swift` is also `#if DEBUG`.
Every seed and reset launch argument lives inside that file, so none of it
compiles into a Release build and no launch argument can reach a shipped app.
There is no developer menu and no production seeding.

## Release checklist

1. `./Scripts/run-tests.sh` — all six batches green
2. Debug build clean
3. Release build clean, zero warnings
4. Bump `CURRENT_PROJECT_VERSION` if this is not the first upload
5. Confirm icon, display name, version and build
6. Install on a physical iPhone and run the core workflow
7. Force quit, relaunch, confirm data survives
8. Export a PDF and a backup; restore the backup
9. Archive, validate, upload
10. `git status` clean; no backups, PDFs, or signing material committed

## Known V1 limitations

Deliberate scope, not defects:

- No bank connection and no automatic import; entry is manual by design
- No cloud sync. One device, plus manual backup/restore to move
- Backups are manual and plaintext
- Restore replaces the notebook; there is no merge
- Closed months cannot be reopened
- Duplicate category names are allowed within a month
- English only, and amounts follow the device locale's currency formatting;
  there is no currency picker
- iPhone only

## Moving to a new iPhone

There is no automatic transfer. The supported path is:

```
Old iPhone  → Settings → Export Backup → save or AirDrop the .financebackup
New iPhone  → install Finance Notebook → Settings → Restore Backup
```

Deleting the app deletes the local store. Export first.
