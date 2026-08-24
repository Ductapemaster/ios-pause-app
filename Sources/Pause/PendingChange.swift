import PauseCore
import SwiftUI

/// What is scheduled for one app, and the day it starts.
///
/// Only a loosening is ever scheduled, so there are two kinds: the app leaves
/// Pause, or its allowance rises. Adding an app is a tightening and applies at
/// once, so it never appears here.
struct PendingRuleChange: Equatable {
    enum Kind: Equatable {
        case removal
        case allowance(sessionsPerDay: Int?, sessionLengthMinutes: Int?)
    }

    let kind: Kind
    let startDay: CalendarDay
}

extension PendingRuleChange.Kind {
    /// Leaving Pause is not the same event as a longer session, and the list is
    /// what gets scanned to see what is about to happen.
    var symbolName: String {
        switch self {
        case .removal: "calendar.badge.minus"
        case .allowance: "calendar.badge.clock"
        }
    }

    /// The symbol carries no text, so it needs one for VoiceOver.
    var accessibilityLabel: String {
        switch self {
        case .removal: "Being removed"
        case .allowance: "Allowance changing"
        }
    }

    var cancelTitle: String {
        switch self {
        case .removal: "Cancel removal"
        case .allowance: "Cancel change"
        }
    }
}

/// A scheduled change to the global settings. Only a shorter pause loosens, so
/// that is the only thing this can carry.
struct PendingSettingsChange: Equatable {
    let pauseSeconds: Int
    let startDay: CalendarDay
}
