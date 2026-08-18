import Foundation

public enum RulesEngine {
    public static func decision(
        rule: AppRule,
        runtime: RuleRuntime,
        today: CalendarDay,
        now: Date
    ) -> SessionDecision {
        var currentRuntime = runtime
        currentRuntime.rollOver(to: today)
        currentRuntime.clearExpiredSession(at: now)

        if let openSession = currentRuntime.openSession {
            return .refused(.sessionAlreadyOpen(until: openSession.expiresAt))
        }

        guard currentRuntime.sessionsStarted < rule.sessionsPerDay else {
            return .refused(.dailyAllowanceExhausted(limit: rule.sessionsPerDay))
        }

        return .allowed(
            sessionNumber: currentRuntime.sessionsStarted + 1,
            lengthMinutes: rule.sessionLengthMinutes
        )
    }
}
