import Foundation
import XCTest

/// The probe is an instrument for a device question its own tests cannot answer:
/// whether an extension's sandbox refuses file operations in the app group
/// container. What these tests establish is the control reading — that the probe
/// reports `permitted` where the operations genuinely succeed, and names the
/// step and errno where they genuinely fail. Without that, a `refused` on device
/// would confound a sandbox denial with a defect in the probe.
final class AppGroupSandboxProbeTests: XCTestCase {
    func testProbeReportsPermittedInADirectoryItCanWrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = AppGroupSandboxProbe.run(directoryURL: directory, filename: "probe")

        XCTAssertEqual(outcome, .permitted)
        XCTAssertEqual(outcome.summary, "app group file I/O permitted")
    }

    func testProbeLeavesItsFileBehindRatherThanTouchingSharedState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = AppGroupSandboxProbe.run(directoryURL: directory, filename: "probe")

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            ["probe"]
        )
    }

    func testProbeNamesTheOpenStepAndErrnoWhenTheDirectoryIsUnwritable() throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        let outcome = AppGroupSandboxProbe.run(directoryURL: directory, filename: "probe")

        guard case let .refused(step, code, _) = outcome else {
            return XCTFail("Expected a refusal, got \(outcome)")
        }
        XCTAssertEqual(step, .open)
        XCTAssertEqual(code, EACCES)
        XCTAssertTrue(outcome.summary.hasPrefix("app group file I/O refused at open: 13 "))
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
