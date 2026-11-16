import SwiftUI
import WidgetKit
import GrindCore

struct GrindEntry: TimelineEntry {
    let date: Date
    let summary: StreakSummary
    let week: [DayDot]
    let hasData: Bool
}

struct DayDot: Identifiable {
    let id: String
    let label: String
    let seconds: Double
    let done: Bool
    let isToday: Bool
}

struct GrindProvider: TimelineProvider {
    func placeholder(in context: Context) -> GrindEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (GrindEntry) -> Void) {
        let snapshot = AppGroup.readSnapshot()
        completion(snapshot.map { Self.entry(at: Date(), snapshot: $0) } ?? .sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrindEntry>) -> Void) {
        let now = Date()
        guard let snapshot = AppGroup.readSnapshot() else {
            completion(Timeline(entries: [.empty(now)], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        // One entry now, one when the next day starts (today resets, streak may be at risk).
        let boundary = snapshot.clock.nextBoundary(after: now)
        let entries = [Self.entry(at: now, snapshot: snapshot), Self.entry(at: boundary, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(boundary)))
    }

    static func entry(at date: Date, snapshot: WidgetSnapshot) -> GrindEntry {
        let clock = snapshot.clock
        let today = clock.day(for: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEEE"
        let week = clock.days(endingAt: today, count: 7).map { day -> DayDot in
            let key = clock.key(for: day)
            let seconds = snapshot.totals[key] ?? 0
            return DayDot(id: key, label: formatter.string(from: day), seconds: seconds,
                          done: seconds >= snapshot.goalSeconds, isToday: day == today)
        }
        return GrindEntry(date: date, summary: snapshot.summary(at: date), week: week, hasData: true)
    }
}

extension GrindEntry {
    static let sample = GrindEntry(
        date: Date(),
        summary: StreakSummary(current: 12, longest: 21, todaySeconds: 18 * 60, goalSeconds: 25 * 60),
        week: ["M", "D", "M", "D", "F", "S", "S"].enumerated().map { i, l in
            DayDot(id: "\(i)", label: l, seconds: i == 6 ? 1080 : 1800, done: i != 6, isToday: i == 6)
        },
        hasData: true
    )

    static func empty(_ date: Date) -> GrindEntry {
        GrindEntry(date: date, summary: .empty,
                   week: (0..<7).map { DayDot(id: "\($0)", label: "·", seconds: 0, done: false, isToday: $0 == 6) },
                   hasData: false)
    }
}

// MARK: Views

struct GrindWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GrindEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(URL(string: "grind://start"))
    }

    private var s: StreakSummary { entry.summary }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .foregroundStyle(s.todayDone ? AnyShapeStyle(.emberGradient) : AnyShapeStyle(Color.white.opacity(0.35)))
    }

    private var statusText: String {
        if !entry.hasData { return "Öffne Grind" }
        if s.todayDone { return "Heute geschafft" }
        return "noch \(DurationFormat.minutes(s.remainingSeconds)) min"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                flame.font(.title2)
                Text("\(s.current)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            Text(s.current == 1 ? "Tag Streak" : "Tage Streak")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ProgressView(value: s.progress)
                .tint(s.todayDone ? .green : .ember)
            HStack {
                Text("\(DurationFormat.minutes(s.todaySeconds))/\(DurationFormat.minutes(s.goalSeconds)) min")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                Spacer()
                if s.todayDone { Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green) }
            }
        }
        .containerBackground(for: .widget) { background }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    flame.font(.title)
                    Text("\(s.current)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
                Text(s.current == 1 ? "Tag Streak" : "Tage Streak")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(s.todayDone ? Color.green : Color.ember)
            }
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(entry.week) { day in
                        VStack(spacing: 5) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(day.done ? AnyShapeStyle(.emberGradient) : AnyShapeStyle(Color.ember.opacity(0.45)))
                                        .frame(height: barHeight(day))
                                }
                                .frame(width: 14, height: 58)
                            Text(day.label)
                                .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                                .foregroundStyle(day.isToday ? .primary : .secondary)
                        }
                    }
                }
                Text("Rekord \(s.longest)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { background }
    }

    private func barHeight(_ day: DayDot) -> CGFloat {
        guard day.seconds > 0 else { return 0 }
        let ratio = min(1, day.seconds / max(s.goalSeconds * 2, 1))
        return max(6, 58 * ratio)
    }

    private var circular: some View {
        Gauge(value: s.progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            VStack(spacing: -2) {
                Image(systemName: "flame.fill").font(.system(size: 10))
                Text("\(s.current)").font(.system(.title3, design: .rounded).weight(.bold))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(s.current) \(s.current == 1 ? "Tag" : "Tage") Streak", systemImage: "flame.fill")
                .font(.headline)
                .widgetAccentable()
            Text(statusText)
                .font(.caption)
            ProgressView(value: s.progress)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Text("\(Image(systemName: "flame.fill")) \(s.current) · \(DurationFormat.minutes(s.todaySeconds)) min heute")
            .containerBackground(for: .widget) { Color.clear }
    }

    private var background: some View {
        ZStack {
            Color(white: 0.06)
            RadialGradient(colors: [Color.ember.opacity(s.todayDone ? 0.35 : 0.12), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 220)
        }
    }
}

struct GrindWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GrindStreak", provider: GrindProvider()) { entry in
            GrindWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Dein Streak und die heutige Lernzeit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct GrindWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrindWidget()
    }
}
