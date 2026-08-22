import Darwin
import Foundation

public final class AppGroupFileLock: @unchecked Sendable {
    private let state: AppGroupFileLockState

    public convenience init(directoryURL: URL) {
        self.init(directoryURL: directoryURL, systemCalls: .live)
    }

    init(directoryURL: URL, systemCalls: AppGroupFileLockSystemCalls) {
        let lockURL = directoryURL.appendingPathComponent(SharedIdentifiers.stateLockFilename)
        state = AppGroupFileLockRegistry.shared.state(for: lockURL, systemCalls: systemCalls)
    }

    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try state.withLock(body)
    }
}

struct AppGroupFileLockSystemCalls: Sendable {
    let openFile: @Sendable (String, Int32, mode_t) -> Int32
    let flockFile: @Sendable (Int32, Int32) -> Int32
    let closeFile: @Sendable (Int32) -> Int32
    /// Seconds on a monotonic clock. The wall clock is unusable for a deadline
    /// because it can jump, and the device's is explicitly taken as given.
    let now: @Sendable () -> TimeInterval
    let sleepFor: @Sendable (TimeInterval) -> Void

    init(
        openFile: @escaping @Sendable (String, Int32, mode_t) -> Int32,
        flockFile: @escaping @Sendable (Int32, Int32) -> Int32,
        closeFile: @escaping @Sendable (Int32) -> Int32,
        now: @escaping @Sendable () -> TimeInterval = {
            Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        },
        sleepFor: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.openFile = openFile
        self.flockFile = flockFile
        self.closeFile = closeFile
        self.now = now
        self.sleepFor = sleepFor
    }

    static let live = AppGroupFileLockSystemCalls(
        openFile: { path, flags, mode in Darwin.open(path, flags, mode) },
        flockFile: { descriptor, operation in flock(descriptor, operation) },
        closeFile: { descriptor in Darwin.close(descriptor) }
    )
}

private final class AppGroupFileLockState {
    private let url: URL
    private let systemCalls: AppGroupFileLockSystemCalls
    private let processLock = NSRecursiveLock()
    private var depth = 0
    private var fileDescriptor: Int32 = -1

    init(url: URL, systemCalls: AppGroupFileLockSystemCalls) {
        self.url = url
        self.systemCalls = systemCalls
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        processLock.lock()
        do {
            if depth == 0 {
                try acquireFileLock()
            }
            depth += 1
        } catch {
            processLock.unlock()
            throw error
        }

        let bodyResult = Result { try body() }
        depth -= 1
        if depth == 0 {
            releaseFileLock()
        }
        processLock.unlock()

        return try bodyResult.get()
    }

    /// How long an acquisition waits on a lock another process holds before it
    /// gives up. A blocking `flock` has no deadline, so contention on the main
    /// thread that crosses the scene-update watchdog's ten seconds is a crash.
    /// Failing well inside that turns every such variant into an error a caller
    /// can report.
    private static let acquisitionTimeout: TimeInterval = 2
    private static let retryInterval: TimeInterval = 0.01

    private func acquireFileLock() throws {
        let descriptor = systemCalls.openFile(
            url.path,
            O_CREAT | O_RDWR | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw posixError() }

        let deadline = systemCalls.now() + Self.acquisitionTimeout
        while true {
            if systemCalls.flockFile(descriptor, LOCK_EX | LOCK_NB) == 0 {
                fileDescriptor = descriptor
                return
            }
            let code = errno
            if code == EINTR { continue }
            // Contention is the only condition a wait can resolve. Anything else
            // is a descriptor-level failure that retrying cannot help.
            guard code == EWOULDBLOCK else {
                _ = systemCalls.closeFile(descriptor)
                throw Self.posixError(code)
            }
            guard systemCalls.now() < deadline else {
                _ = systemCalls.closeFile(descriptor)
                throw POSIXError(.ETIMEDOUT)
            }
            systemCalls.sleepFor(Self.retryInterval)
        }
    }

    private func releaseFileLock() {
        let descriptor = fileDescriptor
        fileDescriptor = -1
        var unlockResult: Int32
        repeat {
            unlockResult = systemCalls.flockFile(descriptor, LOCK_UN)
        } while unlockResult != 0 && errno == EINTR

        // The body has already committed shared state. Unlock and close are
        // therefore best-effort cleanup: reporting either failure as a failed
        // transaction would invite callers to retry or roll back committed work.
        // close(2) releases a held flock even when explicit unlock failed. Do
        // not retry an interrupted close because the descriptor may be closed.
        _ = systemCalls.closeFile(descriptor)
    }

    private func posixError() -> POSIXError {
        Self.posixError(errno)
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}

private final class AppGroupFileLockRegistry: @unchecked Sendable {
    static let shared = AppGroupFileLockRegistry()

    private let lock = NSLock()
    private var states: [String: AppGroupFileLockState] = [:]

    func state(
        for url: URL,
        systemCalls: AppGroupFileLockSystemCalls
    ) -> AppGroupFileLockState {
        let key = Self.key(for: url)
        lock.lock()
        defer { lock.unlock() }
        if let existing = states[key] { return existing }
        let created = AppGroupFileLockState(url: url, systemCalls: systemCalls)
        states[key] = created
        return created
    }

    /// One key per lock file, whenever it is asked for.
    ///
    /// `standardizedFileURL` and `resolvingSymlinksInPath` both drop a leading
    /// `/private` only for a path that already exists, so the lock file has one
    /// spelling before it is created and another afterwards. Keying on either one
    /// therefore hands out a second state to any lock built after the first
    /// acquisition, and the two states then contend for the same file: the second
    /// `flock(LOCK_EX)` waits on a lock this process already holds and never
    /// returns. The containing directory exists whenever a lock is usable, so
    /// resolving that instead gives the same key at every call.
    private static func key(for url: URL) -> String {
        let directoryPath = url.deletingLastPathComponent().path
        guard let resolved = realpath(directoryPath, nil) else {
            return url.standardizedFileURL.path
        }
        defer { free(resolved) }
        return String(cString: resolved) + "/" + url.lastPathComponent
    }
}
