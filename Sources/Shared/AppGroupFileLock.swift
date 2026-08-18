import Darwin
import Foundation

public final class AppGroupFileLock: @unchecked Sendable {
    private let state: AppGroupFileLockState

    public init(directoryURL: URL) {
        let lockURL = directoryURL.appendingPathComponent(SharedIdentifiers.stateLockFilename)
        state = AppGroupFileLockRegistry.shared.state(for: lockURL)
    }

    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try state.withLock(body)
    }
}

private final class AppGroupFileLockState {
    private let url: URL
    private let processLock = NSRecursiveLock()
    private var depth = 0
    private var fileDescriptor: Int32 = -1

    init(url: URL) {
        self.url = url
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
        var releaseError: Error?
        if depth == 0 {
            do {
                try releaseFileLock()
            } catch {
                releaseError = error
            }
        }
        processLock.unlock()

        switch bodyResult {
        case let .success(value):
            if let releaseError { throw releaseError }
            return value
        case let .failure(error):
            throw error
        }
    }

    private func acquireFileLock() throws {
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError() }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            let error = posixError()
            close(descriptor)
            throw error
        }
        fileDescriptor = descriptor
    }

    private func releaseFileLock() throws {
        let descriptor = fileDescriptor
        fileDescriptor = -1
        var unlockResult: Int32
        repeat {
            unlockResult = flock(descriptor, LOCK_UN)
        } while unlockResult != 0 && errno == EINTR
        let unlockError = unlockResult == 0 ? nil : posixError()
        let closeResult = close(descriptor)
        if let unlockError { throw unlockError }
        guard closeResult == 0 else { throw posixError() }
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private final class AppGroupFileLockRegistry: @unchecked Sendable {
    static let shared = AppGroupFileLockRegistry()

    private let lock = NSLock()
    private var states: [String: AppGroupFileLockState] = [:]

    func state(for url: URL) -> AppGroupFileLockState {
        let key = url.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        if let existing = states[key] { return existing }
        let created = AppGroupFileLockState(url: url)
        states[key] = created
        return created
    }
}
