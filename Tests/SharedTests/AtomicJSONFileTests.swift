import FamilyControls
import ManagedSettings
@testable import PauseCore
import XCTest

final class AtomicJSONFileTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        directoryURL = nil
    }

    func testSaveThenLoadRoundTripsConfigurationDocument() throws {
        let file = AtomicJSONFile<ConfigurationDocument>(url: directoryURL.appendingPathComponent("configuration.json"))
        let document = try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10),
            rules: [],
            targets: []
        )

        try file.save(document)

        XCTAssertEqual(try file.load(), document)
    }

    func testSavingReplacementLeavesNewCompleteConfigurationDocument() throws {
        let file = AtomicJSONFile<ConfigurationDocument>(url: directoryURL.appendingPathComponent("configuration.json"))
        let first = try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10),
            rules: [],
            targets: []
        )
        let replacement = try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 20),
            rules: [],
            targets: []
        )
        try file.save(first)

        try file.save(replacement)

        XCTAssertEqual(try file.load(), replacement)
    }

    func testLoadMissingFileReturnsNil() throws {
        let file = AtomicJSONFile<ConfigurationDocument>(url: directoryURL.appendingPathComponent("configuration.json"))

        XCTAssertNil(try file.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testLoadInvalidJSONThrowsCorruptFile() throws {
        let file = AtomicJSONFile<ConfigurationDocument>(url: directoryURL.appendingPathComponent("configuration.json"))
        try Data("not json".utf8).write(to: file.url)

        XCTAssertThrowsError(try file.load()) { error in
            XCTAssertEqual(error as? PersistenceError, .corruptFile(file.url))
        }
    }

    func testConfigurationStoreRejectsRuleWithoutExactlyOneTarget() throws {
        let store = ConfigurationStore(directoryURL: directoryURL)
        let ruleID = UUID(uuidString: "A1623BFB-03A7-47D4-A1B5-9ECFC4F47DE4")!
        let document = try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10),
            rules: [AppRule(id: ruleID, sessionsPerDay: 1, sessionLengthMinutes: 15)],
            targets: []
        )

        let file = ConfigurationFile(effective: document, pending: nil)
        XCTAssertThrowsError(try store.save(file: file)) { error in
            XCTAssertEqual(error as? ConfigurationError, .missingTarget(ruleID))
        }
        XCTAssertNil(try store.loadFile())
    }

    func testLoadRejectsMismatchedConfigurationWithoutChangingItsJSON() throws {
        let store = ConfigurationStore(directoryURL: directoryURL)
        let ruleID = UUID(uuidString: "A1623BFB-03A7-47D4-A1B5-9ECFC4F47DE4")!
        let document = try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10),
            rules: [AppRule(id: ruleID, sessionsPerDay: 1, sessionLengthMinutes: 15)],
            targets: []
        )
        let configurationURL = directoryURL.appendingPathComponent("configuration.json")
        let originalData = try JSONEncoder().encode(document)
        try originalData.write(to: configurationURL)

        XCTAssertThrowsError(try store.loadFile()) { error in
            XCTAssertEqual(error as? ConfigurationError, .missingTarget(ruleID))
        }
        XCTAssertEqual(try Data(contentsOf: configurationURL), originalData)
    }

    func testInstagramLaunchRouteUsesPublicApplicationMetadata() {
        XCTAssertEqual(
            LaunchRoute.detected(for: ManagedSettings.Application(bundleIdentifier: "com.burbn.instagram")),
            .instagram
        )
        XCTAssertNil(LaunchRoute.detected(for: ManagedSettings.Application(bundleIdentifier: "com.example.other")))
        XCTAssertNil(
            LaunchRoute.detected(
                bundleIdentifier: "com.example.same-name",
                localizedDisplayName: "Instagram"
            )
        )
    }

    func testConsumeMissingIntentReturnsNil() throws {
        let suiteName = "AtomicJSONFileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShieldIntentStore(defaults: defaults)

        XCTAssertNil(try store.consume())
    }

    func testConsumeInvalidIntentRemovesItBeforeReportingCorruption() throws {
        let suiteName = "AtomicJSONFileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShieldIntentStore(defaults: defaults)
        defaults.set(Data("not json".utf8), forKey: SharedIdentifiers.shieldIntentKey)

        XCTAssertThrowsError(try store.consume())
        XCTAssertNil(defaults.data(forKey: SharedIdentifiers.shieldIntentKey))
    }
}
