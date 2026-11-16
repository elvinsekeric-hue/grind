import Foundation

/// Maps moments to "logical days". A day starts at `dayStartHour` (e.g. 4:00),
/// so a session at 1:30 at night still counts for the previous day.
public struct DayClock: Sendable, Equatable {
    public var calendar: Calendar
    public var dayStartHour: Int

    public init(calendar: Calendar = .current, dayStartHour: Int = 4) {
        self.calendar = calendar
        self.dayStartHour = min(max(dayStartHour, 0), 12)
    }

    /// Midnight of the calendar date the moment belongs to.
    public func day(for date: Date) -> Date {
        let midnight = calendar.startOfDay(for: date)
        guard dayStartHour > 0,
              let boundary = calendar.date(byAdding: .hour, value: dayStartHour, to: midnight)
        else { return midnight }
        if date < boundary {
            let previous = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
            return calendar.startOfDay(for: previous)
        }
        return midnight
    }

    /// The moment a logical day begins.
    public func start(ofDay day: Date) -> Date {
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: dayStartHour, to: midnight) ?? midnight
    }

    /// The next moment a new logical day begins.
    public func nextBoundary(after date: Date) -> Date {
        let today = day(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        return start(ofDay: tomorrow)
    }

    public func adding(days: Int, to day: Date) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: day) ?? day)
    }

    /// Stable string key "yyyy-MM-dd" for a logical day.
    public func key(for day: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func key(forMoment date: Date) -> String {
        key(for: self.day(for: date))
    }

    public func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c).map { calendar.startOfDay(for: $0) }
    }

    /// `count` logical days ending with `day` (oldest first).
    public func days(endingAt day: Date, count: Int) -> [Date] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { adding(days: -$0, to: day) }
    }

    public func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}
