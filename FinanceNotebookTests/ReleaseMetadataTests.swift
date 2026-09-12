import XCTest
@testable import FinanceNotebook

/// Release identity and privacy declarations, checked against the built bundle
/// rather than against constants in the source. These exist because the values
/// they cover are edited in the Xcode project, where nothing else would notice
/// a mistake until an upload was rejected.
final class ReleaseMetadataTests: XCTestCase {

    /// Unit tests here are hosted by the app, so `main` is the app bundle --
    /// which is the one whose shipped metadata these tests are about.
    private var app: Bundle { .main }

    func testTheDisplayNameIsTheProductName() {
        let name = app.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        XCTAssertEqual(name, "Finance Notebook",
                       "The Home Screen name must read as a product, not as a target name")
    }

    func testTheBundleIdentifierIsTheProductionOne() {
        XCTAssertEqual(app.bundleIdentifier, "com.mathewabraham.FinanceNotebook")
    }

    func testVersionAndBuildArePresentAndWellFormed() {
        let version = app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = app.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        XCTAssertNotNil(version)
        XCTAssertNotNil(build)

        // Settings renders these directly, so anything unparseable would show.
        let versionParts = (version ?? "").split(separator: ".")
        XCTAssertFalse(versionParts.isEmpty, "Marketing version should be dotted numerals")
        XCTAssertTrue(versionParts.allSatisfy { Int($0) != nil },
                      "Marketing version should be dotted numerals, got \(version ?? "nil")")
        XCTAssertNotNil(Int(build ?? ""), "Build should be an integer for TestFlight ordering")
    }

    /// Guards the claim Settings makes to the user.
    func testThePrivacyManifestDeclaresNoTrackingAndNoCollection() throws {
        let url = try XCTUnwrap(app.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "The privacy manifest is not in the app bundle")
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil
            ) as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0,
                       "A tracking domain would contradict having no networking")
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0,
                       "Nothing is collected; the store listing says so")
    }

    /// UserDefaults is a required-reason API and MonthSelection uses it, so the
    /// declaration has to stay even though nothing else does.
    func testTheUserDefaultsReasonIsDeclared() throws {
        let url = try XCTUnwrap(app.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil
            ) as? [String: Any]
        )
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

        let defaults = apis.first {
            $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = try XCTUnwrap(
            defaults?["NSPrivacyAccessedAPITypeReasons"] as? [String],
            "UserDefaults access must be declared with a reason"
        )
        XCTAssertTrue(reasons.contains("CA92.1"),
                      "CA92.1 is the reason for reading the app's own defaults")
    }

    func testTheAppIconIsBuiltIntoTheBundle() {
        // Xcode compiles the asset catalog, so the icon is only really present
        // if a rendered PNG came out the other side.
        let icons = app.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String]
        XCTAssertNotNil(files, "No app icon was compiled into the bundle")
        XCTAssertFalse(files?.isEmpty ?? true, "The app icon set produced no images")
    }
}
