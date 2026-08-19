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
        let startedURL = directory.appendingPathComponent("child-started")
        let acquiredURL = directory.appendingPathComponent("child-acquired")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = [directory.path, "child"]

        try AppGroupFileLock(directoryURL: directory).withLock {
            try child.run()
            guard waitForFile(startedURL, timeout: 2) else {
                throw ProcessTestError.childDidNotStart
            }
            guard !FileManager.default.fileExists(atPath: acquiredURL.path) else {
                throw ProcessTestError.childEnteredHeldLock
            }
        }

        child.waitUntilExit()
        guard child.terminationStatus == 0 else {
            throw ProcessTestError.childFailed(child.terminationStatus)
        }
        guard FileManager.default.fileExists(atPath: acquiredURL.path) else {
            throw ProcessTestError.childNeverAcquiredLock
        }
        print("cross-process AppGroupFileLock serialization passed")
    }

    private static func runChild(in directory: URL) throws {
        try Data().write(to: directory.appendingPathComponent("child-started"))
        try AppGroupFileLock(directoryURL: directory).withLock {
            try Data().write(to: directory.appendingPathComponent("child-acquired"))
        }
    }

    private static func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
}

private enum ProcessTestError: LocalizedError {
    case missingDirectory
    case childDidNotStart
    case childEnteredHeldLock
    case childFailed(Int32)
    case childNeverAcquiredLock

    var errorDescription: String? {
        switch self {
        case .missingDirectory: "The test directory argument is missing."
        case .childDidNotStart: "The child process did not start."
        case .childEnteredHeldLock: "The child entered while the parent held the lock."
        case let .childFailed(status): "The child process exited with status \(status)."
        case .childNeverAcquiredLock: "The child never acquired the released lock."
        }
    }
}
