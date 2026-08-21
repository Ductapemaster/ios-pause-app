import Foundation

public struct RuleRemovalFailure: LocalizedError {
    public let primaryError: Error
    public let repairErrors: [Error]

    public init(primaryError: Error, repairErrors: [Error]) {
        self.primaryError = primaryError
        self.repairErrors = repairErrors
    }

    public var errorDescription: String? {
        let primary = "The app removal failed (\(primaryError.localizedDescription))."
        guard !repairErrors.isEmpty else { return primary }
        let repairs = repairErrors.map(\.localizedDescription).joined(separator: "; ")
        return "\(primary) Repair also failed: \(repairs)."
    }
}
