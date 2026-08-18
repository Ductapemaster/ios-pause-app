import Foundation

public enum SessionActivityName {
    public static let prefix = "session."

    public static func sessionActivityName(for ruleID: UUID) -> String {
        prefix + ruleID.uuidString.lowercased()
    }

    public static func ruleID(fromSessionActivityName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }
}
