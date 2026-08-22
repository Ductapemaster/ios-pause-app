import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationStoreFileTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let ruleID = UUID()

    func testAFileSurvivesASaveAndLoad() throws {
        let directoryURL = try temporaryDirectory()
        let store = ConfigurationStore(directoryURL: directoryURL)
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        try store.save(file: file)

        XCTAssertEqual(try store.loadFile(), file)
    }

    func testABareDocumentFromAnOlderBuildLoadsAsTheEffectiveOne() throws {
        let directoryURL = try temporaryDirectory()
        let legacy = try document(sessionsPerDay: 3)
        try AtomicJSONFile<ConfigurationDocument>(
            url: directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        ).save(legacy)

        let loaded = try ConfigurationStore(directoryURL: directoryURL).loadFile()

        XCTAssertEqual(loaded, ConfigurationFile(effective: legacy, pending: nil))
    }

    func testACorruptFileInTheCurrentShapeIsReportedAsCorrupt() throws {
        let directoryURL = try temporaryDirectory()
        let url = directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        try Data(#"{"effective": {"rules": 7}}"#.utf8).write(to: url)

        XCTAssertThrowsError(try ConfigurationStore(directoryURL: directoryURL).loadFile()) { error in
            XCTAssertEqual(error as? PersistenceError, .corruptFile(url))
        }
    }

    func testAnInvalidPendingDocumentIsRefusedOnSave() throws {
        let directoryURL = try temporaryDirectory()
        let orphanedTarget = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(document: orphanedTarget, startDay: day(2026, 8, 21))
        )

        XCTAssertThrowsError(try ConfigurationStore(directoryURL: directoryURL).save(file: file))
    }

    func testTheLockFreeReadReturnsTheSameFile() throws {
        let directoryURL = try temporaryDirectory()
        let store = ConfigurationStore(directoryURL: directoryURL)
        let file = ConfigurationFile(effective: try document(sessionsPerDay: 3), pending: nil)
        try store.save(file: file)

        XCTAssertEqual(try store.loadFileWithoutLocking(), file)
    }

    // MARK: - Helpers

    private func document(sessionsPerDay: Int) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> CalendarDay {
        CalendarDay(
            date: calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!,
            calendar: calendar
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-config-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
