import SwiftData
import SwiftUI
import GrindCore

struct HomeView: View {
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]
    @AppStorage(Pref.goalMinutes) private var goalMinutes = 25
    @AppStorage(Pref.dayStartHour) private var dayStartHour = 4
    let onStart: () -> Void

    private var clock: DayClock { DayClock(dayStartHour: dayStartHour) }
    private var goal: Double { Double(goalMinutes * 60) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let totals = Aggregation.dailyTotals(sessions.map(\.sample), clock: clock)
                let summary = StreakCalculator.summarize(totals: totals, goalSeconds: goal, now: timeline.date, clock: clock)

                ScrollView {
                    VStack(spacing: 18) {
                        StreakHero(summary: summary)
                        startButton
                        WeekStrip(totals: totals, goal: goal, clock: clock, now: timeline.date)
                        weekNumbers(totals: totals, now: timeline.date)
                        recent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(background)
            }
            .navigationTitle("Grind")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    private var background: some View {
        RadialGradient(colors: [Color.ember.opacity(0.18), .black], center: .top, startRadius: 0, endRadius: 520)
            .ignoresSafeArea()
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                Text("Session starten")
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .tint(.ember)
    }

    private func weekNumbers(totals: [String: Double], now: Date) -> some View {
        let today = clock.day(for: now)
        let week = clock.days(endingAt: today, count: 7).reduce(0) { $0 + (totals[clock.key(for: $1)] ?? 0) }
        let month = clock.days(endingAt: today, count: 30).reduce(0) { $0 + (totals[clock.key(for: $1)] ?? 0) }
        let all = totals.values.reduce(0, +)
        return HStack(spacing: 10) {
            NumberTile(value: DurationFormat.hours(week), label: "7 Tage")
            NumberTile(value: DurationFormat.hours(month), label: "30 Tage")
            NumberTile(value: DurationFormat.hours(all), label: "Gesamt")
        }
    }

    @ViewBuilder
    private var recent: some View {
        if sessions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.emberGradient)
                Text("Noch keine Sessions")
                    .font(.headline)
                Text("Starte deine erste Session. Ab \(goalMinutes) Minuten am Tag wächst dein Streak.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .card()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Letzte Sessions")
                    .font(.headline)
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        if index < min(sessions.count, 6) - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .card()
            }
        }
    }
}

struct StreakHero: View {
    let summary: StreakSummary
    @State private var flicker = false

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(summary.todayDone ? AnyShapeStyle(.emberGradient) : AnyShapeStyle(Color.white.opacity(0.3)))
                        .symbolEffect(.breathe, isActive: summary.todayDone)
                        .shadow(color: summary.todayDone ? .ember.opacity(0.6) : .clear, radius: 16)
                    Text("\(summary.current)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(summary.current == 1 ? "Tag Streak" : "Tage Streak")
                    .font(.headline)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(summary.todayDone ? Color.green : .secondary)
                if summary.longest > 0 {
                    Label("Rekord \(summary.longest) \(summary.longest == 1 ? "Tag" : "Tage")", systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            ProgressRing(progress: summary.progress, lineWidth: 12) {
                VStack(spacing: 0) {
                    Text("\(DurationFormat.minutes(summary.todaySeconds))")
                        .font(.title.weight(.bold).monospacedDigit())
                    Text("/ \(DurationFormat.minutes(summary.goalSeconds)) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
        }
        .padding(20)
        .card()
    }

    private var status: String {
        if summary.todayDone { return "Heute geschafft ✓" }
        if summary.current > 0 { return "Noch \(DurationFormat.short(summary.remainingSeconds)), sonst reißt der Streak" }
        return "Noch \(DurationFormat.short(summary.remainingSeconds)) für heute"
    }
}

struct ProgressRing<Label: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(AngularGradient(colors: [.emberDeep, .ember, .emberGlow], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8), value: progress)
            label()
        }
    }
}

struct WeekStrip: View {
    let totals: [String: Double]
    let goal: Double
    let clock: DayClock
    let now: Date

    var body: some View {
        let today = clock.day(for: now)
        let days = clock.days(endingAt: today, count: 7)
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let seconds = totals[clock.key(for: day)] ?? 0
                let done = seconds >= goal
                let isToday = day == today
                VStack(spacing: 8) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Color.primary : .secondary)
                    ZStack {
                        Circle()
                            .fill(done ? Color.ember : Color.white.opacity(0.07))
                        Circle()
                            .trim(from: 0, to: done ? 0 : min(1, seconds / max(goal, 1)))
                            .stroke(Color.ember, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(1.5)
                        if done {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        if isToday { Circle().stroke(Color.white.opacity(0.6), lineWidth: 1).padding(-4) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .card()
    }
}

struct NumberTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .card()
    }
}

struct SessionRow: View {
    let session: StudySession

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: session.thumbnailURL, symbol: session.subject?.symbol ?? "book.fill", tint: session.subjectColor)
                .frame(width: 48, height: 64)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.subjectName)
                    .font(.subheadline.weight(.semibold))
                Text(session.startedAt.formatted(.dateTime.weekday(.wide).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormat.short(session.activeSeconds))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if session.interruptions > 0 {
                    Label("\(session.interruptions)", systemImage: "arrow.uturn.left")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct Thumbnail: View {
    let url: URL?
    var symbol: String = "book.fill"
    var tint: Color = .ember

    var body: some View {
        if let url, let image = ThumbnailCache.image(for: url) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                tint.opacity(0.2)
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
        }
    }
}

@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for url: URL) -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

extension View {
    func card() -> some View {
        background(Color.surface.opacity(0.85), in: .rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}
