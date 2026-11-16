import Foundation

/// Everything the widget needs. Written by the app into the shared App Group container.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var goalSeconds: Double
    public var dayStartHour: Int
    /// Active seconds per logical day key ("yyyy-MM-dd").
    public var totals: [String: Double]

    public init(generatedAt: Date, goalSeconds: Double, dayStartHour: Int, totals: [String: Double]) {
        self.generatedAt = generatedAt
        self.goalSeconds = goalSeconds
        self.dayStartHour = dayStartHour
        self.totals = totals
    }

    public static let fileName = "widget-snapshot.json"

    public var clock: DayClock { DayClock(dayStartHour: dayStartHour) }

    public func summary(at date: Date) -> StreakSummary {
        StreakCalculator.summarize(totals: totals, goalSeconds: goalSeconds, now: date, clock: clock)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}
