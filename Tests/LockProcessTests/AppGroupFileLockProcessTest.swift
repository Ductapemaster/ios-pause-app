import Darwin
import Foundation

@main
private enum AppGroupFileLockProcessTest {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw ProcessTestError.missingDirectory
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if CommandLine.arguments.last == "child" {
            try runChild(in: directory)
        } else {
            try runParent(in: directory)
        }
    }

    private static func runParent(in directory: URL) throws {
        let resultURL = directory.appendingPathComponent("child-result")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = [directory.path, "child"]

        let contentionResult = try AppGroupFileLock(directoryURL: directory).withLock {
            try child.run()
            guard let result = waitForResult(resultURL, timeout: 2) else {
                throw ProcessTestError.childDidNotReportContention
            }
            return result
        }

        child.waitUntilExit()
        guard contentionResult == "contended" else {
            throw ProcessTestError.childEnteredHeldLock(contentionResult)
        }
        guard child.terminationStatus == 0 else {
            throw ProcessTestError.childFailed(child.terminationStatus)
        }
        guard try String(contentsOf: resultURL, encoding: .utf8) == "acquired" else {
            throw ProcessTestError.childNeverAcquiredLock
        }
        print("cross-process AppGroupFileLock serialization passed")
    }

    private static func runChild(in directory: URL) throws {
        let lockURL = directory.appendingPathComponent(SharedIdentifiers.stateLockFilename)
        let resultURL = directory.appendingPathComponent("child-result")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let nonblockingResult = flock(descriptor, LOCK_EX | LOCK_NB)
        if nonblockingResult == 0 {
            try "unexpected-acquire".write(to: resultURL, atomically: true, encoding: .utf8)
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
            return
        }
        let contentionError = errno
        _ = Darwin.close(descriptor)
        guard contentionError == EWOULDBLOCK || contentionError == EAGAIN else {
            throw POSIXError(POSIXErrorCode(rawValue: contentionError) ?? .EIO)
        }
        try "contended".write(to: resultURL, atomically: true, encoding: .utf8)

        try AppGroupFileLock(directoryURL: directory).withLock {
            try "acquired".write(to: resultURL, atomically: true, encoding: .utf8)
        }
    }

    private static func waitForResult(_ url: URL, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = try? String(contentsOf: url, encoding: .utf8) {
                if ["contended", "unexpected-acquire", "acquired"].contains(result) {
                    return result
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }
}

private enum ProcessTestError: LocalizedError {
    case missingDirectory
    case childDidNotReportContention
    case childEnteredHeldLock(String)
    case childFailed(Int32)
    case childNeverAcquiredLock

    var errorDescription: String? {
        switch self {
        case .missingDirectory: "The test directory argument is missing."
        case .childDidNotReportContention:
            "The child process did not report its nonblocking lock attempt."
        case let .childEnteredHeldLock(result):
            "The child entered while the parent held the lock (reported \(result))."
        case let .childFailed(status): "The child process exited with status \(status)."
        case .childNeverAcquiredLock: "The child never acquired the released lock."
        }
    }
}
