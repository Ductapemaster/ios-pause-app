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
        case .removal: "minus.circle.fill"
        case .allowance: "calendar.badge.clock"
        }
    }

    /// The two kinds must read apart by outline shape as well as by colour,
    /// so the distinction survives greyscale and red/green colourblindness
    /// rather than resting on colour alone.
    var tint: Color {
        switch self {
        case .removal: .red
        case .allowance: .accentColor
        }
    }

    /// `nil` keeps the default tint; `.destructive` follows the platform's
    /// own styling rather than a hand-picked colour, so it can never drift
    /// from `tint` above.
    var cancelRole: ButtonRole? {
        switch self {
        case .removal: .destructive
        case .allowance: nil
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
