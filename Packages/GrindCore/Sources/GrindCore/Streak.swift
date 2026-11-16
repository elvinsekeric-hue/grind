import Foundation

public struct SessionSample: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var activeSeconds: Double
    public var subjectID: UUID?

    public init(start: Date, end: Date, activeSeconds: Double, subjectID: UUID? = nil) {
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.subjectID = subjectID
    }
}

public enum Aggregation {
    /// Active seconds per logical day key. A session counts for the day it started.
    public static func dailyTotals(_ sessions: [SessionSample], clock: DayClock) -> [String: Double] {
        var totals: [String: Double] = [:]
        for s in sessions where s.activeSeconds > 0 {
            totals[clock.key(forMoment: s.start), default: 0] += s.activeSeconds
        }
        return totals
    }

    /// Active seconds per hour of day (0...23). Active time is spread evenly over
    /// the wall-clock span of the session.
    public static func hourHistogram(_ sessions: [SessionSample], calendar: Calendar) -> [Double] {
        var buckets = Array(repeating: 0.0, count: 24)
        for s in sessions where s.activeSeconds > 0 {
            let span = max(s.end.timeIntervalSince(s.start), 1)
            let ratio = min(s.activeSeconds / span, 1)
            var cursor = s.start
            while cursor < s.end {
                let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                let hourEnd = min(hourStart.addingTimeInterval(3600), s.end)
                let hour = calendar.component(.hour, from: cursor)
                buckets[hour] += hourEnd.timeIntervalSince(cursor) * ratio
                if hourEnd <= cursor { break }
                cursor = hourEnd
            }
            if s.end <= s.start {
                buckets[calendar.component(.hour, from: s.start)] += s.activeSeconds
            }
        }
        return buckets
    }
}

public struct StreakSummary: Sendable, Equatable {
    public var current: Int
    public var longest: Int
    public var todaySeconds: Double
    public var goalSeconds: Double

    public init(current: Int, longest: Int, todaySeconds: Double, goalSeconds: Double) {
        self.current = current
        self.longest = longest
        self.todaySeconds = todaySeconds
        self.goalSeconds = goalSeconds
    }

    public var todayDone: Bool { todaySeconds >= goalSeconds }
    public var progress: Double { goalSeconds > 0 ? min(1, todaySeconds / goalSeconds) : 1 }
    public var remainingSeconds: Double { max(0, goalSeconds - todaySeconds) }

    public static let empty = StreakSummary(current: 0, longest: 0, todaySeconds: 0, goalSeconds: 25 * 60)
}

public enum StreakCalculator {
    public static func summarize(totals: [String: Double], goalSeconds: Double, now: Date, clock: DayClock) -> StreakSummary {
        let goal = max(goalSeconds, 1)
        let today = clock.day(for: now)
        func qualifies(_ day: Date) -> Bool { totals[clock.key(for: day), default: 0] >= goal }

        var current = 0
        var cursor = qualifies(today) ? today : clock.adding(days: -1, to: today)
        while qualifies(cursor) {
            current += 1
            cursor = clock.adding(days: -1, to: cursor)
        }

        let qualifyingDays = totals
            .filter { $0.value >= goal }
            .compactMap { clock.date(fromKey: $0.key) }
            .sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in qualifyingDays {
            if let p = previous, clock.daysBetween(p, day) == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }

        return StreakSummary(
            current: current,
            longest: max(longest, current),
            todaySeconds: totals[clock.key(for: today), default: 0],
            goalSeconds: goal
        )
    }
}
