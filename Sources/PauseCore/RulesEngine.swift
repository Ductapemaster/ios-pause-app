import Foundation

public enum RulesEngine {
    /// The cooldown is asked after the allowance, not before it. A cooldown is
    /// meaningless for an app with no sessions left, so the question only arises
    /// once a session is available to start. That is also what makes the daily
    /// reset need no handling of its own: the reset returns the allowance, which
    /// makes the cooldown question live again, answered from the same stamp.
    public static func decision(
        rule: AppRule,
        runtime: RuleRuntime,
        settings: GlobalSettings,
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

        if let cooldownEnd = cooldownEnd(runtime: currentRuntime, settings: settings),
           cooldownEnd > now {
            return .refused(.coolingDown(until: cooldownEnd))
        }

        return .allowed(
            sessionNumber: currentRuntime.sessionsStarted + 1,
            lengthMinutes: rule.sessionLengthMinutes
        )
    }

    /// When the cooldown following the last session ends, or nothing when the
    /// cooldown is switched off or no session has expired yet.
    public static func cooldownEnd(
        runtime: RuleRuntime,
        settings: GlobalSettings
    ) -> Date? {
        guard settings.cooldownMinutes > 0, let lastExpiry = runtime.lastSessionExpiry else {
            return nil
        }
        return lastExpiry.addingTimeInterval(Double(settings.cooldownMinutes) * 60)
    }
}
