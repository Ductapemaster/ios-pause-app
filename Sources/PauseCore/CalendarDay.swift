import Foundation

public struct CalendarDay: Codable, Equatable, Comparable, Sendable {
    public let era: Int
    public let year: Int
    public let month: Int
    public let day: Int

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        era = components.era ?? 1
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.era != rhs.era { return lhs.era < rhs.era }
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}
