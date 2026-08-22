import Foundation

public enum SessionActivityName {
    public static let prefix = "session."

    public static func sessionActivityName(for ruleID: UUID) -> String {
        prefix + ruleID.uuidString.lowercased()
    }

    public static func ruleID(fromSessionActivityName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        let identifier = String(name.dropFirst(prefix.count))
        guard identifier.count == 36, identifier == identifier.lowercased() else { return nil }
        return UUID(uuidString: identifier)
    }
}
