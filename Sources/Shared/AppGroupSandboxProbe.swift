import Darwin
import Foundation

/// Reports whether the running process's sandbox permits the file operations
/// every reconcile path depends on, by attempting them against a file of its own
/// in the App Group container.
///
/// A resolved container URL says nothing about this. `ShieldConfigExtension`
/// resolves the same URL and every file operation inside it returns `EPERM`
/// ([the shield repair variant note](../../docs/research/shield-repair-variant.md)),
/// so only an attempted operation separates a permitted container from a refused
/// one. The probe runs the same sequence `AppGroupFileLock` does —
/// `open(O_CREAT|O_RDWR|O_CLOEXEC)`, `flock(LOCK_EX)`, `write`, `flock(LOCK_UN)`
/// — against its own file, and names the step that failed rather than the fact
/// that something did.
///
/// It touches no state any other component reads, so it can run unconditionally
/// on a path whose real work may never be reached.
public enum AppGroupSandboxProbe {
    public enum Step: String, Sendable {
        case resolveContainer
        case open
        case lock
        case write
        case unlock
    }

    public enum Outcome: Sendable, Equatable {
        case permitted
        case refused(step: Step, code: Int32, message: String)

        /// A single log-ready line. `privacy: .public` is safe on it: it carries a
        /// step name and an errno, never a token, a rule or a path.
        public var summary: String {
            switch self {
            case .permitted:
                "app group file I/O permitted"
            case let .refused(step, code, message):
                "app group file I/O refused at \(step.rawValue): \(code) \(message)"
            }
        }
    }

    public static func run(
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        filename: String = SharedIdentifiers.sandboxProbeFilename
    ) -> Outcome {
        let directoryURL: URL
        do {
            directoryURL = try appGroupContainer.directoryURL()
        } catch {
            // Defensive and untested: a simulator resolves this for an app group
            // the process does not hold, so the branch cannot be reached there.
            return .refused(
                step: .resolveContainer,
                code: 0,
                message: String(describing: error)
            )
        }

        return run(directoryURL: directoryURL, filename: filename)
    }

    static func run(directoryURL: URL, filename: String) -> Outcome {
        let path = directoryURL.appendingPathComponent(filename).path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return refusal(at: .open) }
        defer { _ = Darwin.close(descriptor) }

        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            return refusal(at: .lock)
        }

        var byte: UInt8 = 0x70
        let written = Darwin.write(descriptor, &byte, 1)
        if written != 1 { return refusal(at: .write) }

        while flock(descriptor, LOCK_UN) != 0 {
            if errno == EINTR { continue }
            return refusal(at: .unlock)
        }

        return .permitted
    }

    private static func refusal(at step: Step) -> Outcome {
        let code = errno
        return .refused(step: step, code: code, message: String(cString: strerror(code)))
    }
}
