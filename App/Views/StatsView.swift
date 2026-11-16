import Charts
import SwiftData
import SwiftUI
import GrindCore

struct StatsView: View {
    @Query(sort: \StudySession.startedAt) private var sessions: [StudySession]
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @AppStorage(Pref.goalMinutes) private var goalMinutes = 25
    @AppStorage(Pref.dayStartHour) private var dayStartHour = 4

    @State private var range: StatsRange = .week

    enum StatsRange: String, CaseIterable, Identifiable {
        case week = "Woche", month = "Monat", year = "Jahr"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : self == .month ? 30 : 365 }
    }

    private var clock: DayClock { DayClock(dayStartHour: dayStartHour) }
    private var goal: Double { Double(goalMinutes * 60) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if sessions.isEmpty {
                    ContentUnavailableView("Noch keine Daten",
                                           systemImage: "chart.bar.xaxis",
                                           description: Text("Nach deiner ersten Session siehst du hier, wann und was du lernst."))
                        .padding(.top, 80)
                } else {
                    content
                }
            }
            .background(Color.black)
            .navigationTitle("Statistik")
        }
    }

    private var content: some View {
        let allTotals = Aggregation.dailyTotals(sessions.map(\.sample), clock: clock)
        let today = clock.day(for: Date())
        let rangeStart = clock.adding(days: -(range.days - 1), to: today)
        let inRange = sessions.filter { clock.day(for: $0.startedAt) >= rangeStart }
        let summary = StreakCalculator.summarize(totals: allTotals, goalSeconds: goal, now: Date(), clock: clock)

        return VStack(spacing: 16) {
            Picker("Zeitraum", selection: $range) {
                ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            overviewGrid(inRange: inRange, summary: summary)

            ChartCard(title: range == .year ? "Stunden pro Monat" : "Minuten pro Tag") {
                timeChart(inRange: inRange, start: rangeStart, today: today)
            }

            ChartCard(title: "Aktivität", subtitle: "Jedes Feld ist ein Tag. Hell = Ziel deutlich übertroffen.") {
                HeatmapView(totals: allTotals, goal: goal, clock: clock)
            }

            if !inRange.isEmpty {
                ChartCard(title: "Fächer") {
                    subjectBreakdown(inRange)
                }

                ChartCard(title: "Tageszeit", subtitle: "Wann du am meisten lernst") {
                    hourChart(inRange)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .animation(.smooth, value: range)
    }

    // MARK: Overview

    private func overviewGrid(inRange: [StudySession], summary: StreakSummary) -> some View {
        let total = inRange.reduce(0) { $0 + $1.activeSeconds }
        let longest = inRange.map(\.activeSeconds).max() ?? 0
        let days = Double(range.days)
        let goalDays = Aggregation.dailyTotals(inRange.map(\.sample), clock: clock).values.filter { $0 >= goal }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: DurationFormat.hours(total), label: "Gelernt", symbol: "clock.fill", tint: .ember)
            StatTile(value: DurationFormat.short(total / days), label: "Ø pro Tag", symbol: "chart.line.uptrend.xyaxis", tint: .cyan)
            StatTile(value: "\(goalDays)/\(range.days)", label: "Tage mit Ziel", symbol: "checkmark.seal.fill", tint: .green)
            StatTile(value: "\(summary.longest)", label: "Längster Streak", symbol: "trophy.fill", tint: .yellow)
            StatTile(value: "\(inRange.count)", label: "Sessions", symbol: "square.stack.fill", tint: .purple)
            StatTile(value: DurationFormat.short(longest), label: "Längste Session", symbol: "bolt.fill", tint: .pink)
        }
    }

    // MARK: Time chart

    private struct Bar: Identifiable {
        let id = UUID()
        let date: Date
        let subject: String
        let value: Double
    }

    private func timeChart(inRange: [StudySession], start: Date, today: Date) -> some View {
        let isYear = range == .year
        var buckets: [String: Bar] = [:]
        for s in inRange {
            let day = clock.day(for: s.startedAt)
            let bucketDate = isYear ? (clock.calendar.dateInterval(of: .month, for: day)?.start ?? day) : day
            let key = "\(bucketDate.timeIntervalSince1970)-\(s.subjectName)"
            let value = isYear ? s.activeSeconds / 3600 : s.activeSeconds / 60
            let existing = buckets[key]?.value ?? 0
            buckets[key] = Bar(date: bucketDate, subject: s.subjectName, value: existing + value)
        }
        let bars = buckets.values.sorted { $0.date < $1.date }
        let (names, colors) = subjectScale(inRange)

        return Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Datum", bar.date, unit: isYear ? .month : .day),
                    y: .value(isYear ? "Stunden" : "Minuten", bar.value)
                )
                .foregroundStyle(by: .value("Fach", bar.subject))
                .cornerRadius(3)
            }
            if !isYear {
                RuleMark(y: .value("Ziel", Double(goalMinutes)))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Ziel").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartXScale(domain: start...(clock.adding(days: 1, to: today)))
        .chartXAxis {
            if range == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else if range == .month {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            } else {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 12)
        .frame(height: 220)
    }

    private func subjectScale(_ list: [StudySession]) -> ([String], [Color]) {
        var names: [String] = []
        var colors: [Color] = []
        for subject in subjects where !names.contains(subject.name) {
            names.append(subject.name)
            colors.append(subject.color)
        }
        if list.contains(where: { $0.subject == nil }) {
            names.append("Ohne Fach")
            colors.append(.gray)
        }
        return (names, colors)
    }

    // MARK: Subjects

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let color: Color
        let symbol: String
        let seconds: Double
    }

    private func subjectBreakdown(_ list: [StudySession]) -> some View {
        var map: [String: Slice] = [:]
        for s in list {
            let key = s.subject?.id.uuidString ?? "none"
            let prev = map[key]?.seconds ?? 0
            map[key] = Slice(id: key, name: s.subjectName, color: s.subjectColor,
                             symbol: s.subject?.symbol ?? "questionmark", seconds: prev + s.activeSeconds)
        }
        let slices = map.values.sorted { $0.seconds > $1.seconds }
        let total = max(slices.reduce(0) { $0 + $1.seconds }, 1)

        return HStack(alignment: .center, spacing: 18) {
            Chart(slices) { slice in
                SectorMark(angle: .value("Zeit", slice.seconds), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(slice.color)
                    .cornerRadius(4)
            }
            .frame(width: 130, height: 130)
            .overlay {
                VStack(spacing: 0) {
                    Text(DurationFormat.hours(total)).font(.headline.monospacedDigit())
                    Text("gesamt").font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        Image(systemName: slice.symbol)
                            .font(.caption)
                            .foregroundStyle(slice.color)
                            .frame(width: 18)
                        Text(slice.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int((slice.seconds / total * 100).rounded())) %")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Hours

    private func hourChart(_ list: [StudySession]) -> some View {
        let hours = Aggregation.hourHistogram(list.map(\.sample), calendar: clock.calendar)
        let peak = hours.indices.max { hours[$0] < hours[$1] } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(0..<24, id: \.self) { hour in
                    BarMark(x: .value("Stunde", hour), y: .value("Minuten", hours[hour] / 60))
                        .foregroundStyle(hour == peak ? AnyShapeStyle(Color.ember) : AnyShapeStyle(Color.ember.opacity(0.35)))
                        .cornerRadius(2)
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) { Text("\(h) Uhr") }
                    }
                }
            }
            .frame(height: 140)
            Text("Am stärksten zwischen \(peak) und \((peak + 1) % 24) Uhr")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card()
    }
}

/// GitHub-style contribution grid, newest week on the right.
struct HeatmapView: View {
    let totals: [String: Double]
    let goal: Double
    let clock: DayClock

    @State private var selected: Date?
    private let cell: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let columns = max(4, Int((geo.size.width + gap) / (cell + gap)))
                let weeks = buildWeeks(columns: columns)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { w in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { d in
                                cellView(weeks[w][d])
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * cell + 6 * gap)

            HStack(spacing: 6) {
                if let selected {
                    let secs = totals[clock.key(for: selected)] ?? 0
                    Text("\(selected.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(secs > 0 ? DurationFormat.short(secs) : "nichts")")
                        .font(.caption.weight(.semibold))
                        .transition(.opacity)
                } else {
                    Text("Tippe auf einen Tag").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("weniger").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3).fill(HeatLevel.color(level)).frame(width: 10, height: 10)
                }
                Text("mehr").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: Date?) -> some View {
        if let day {
            let secs = totals[clock.key(for: day)] ?? 0
            RoundedRectangle(cornerRadius: 3)
                .fill(HeatLevel.color(HeatLevel.level(seconds: secs, goal: goal)))
                .overlay {
                    if selected == day { RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 1.5) }
                }
                .frame(width: cell, height: cell)
                .onTapGesture {
                    Haptics.tap()
                    withAnimation(.snappy) { selected = selected == day ? nil : day }
                }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    /// Weeks (Mon...Sun) as columns, ending with the current week. Future days are nil.
    private func buildWeeks(columns: Int) -> [[Date?]] {
        let today = clock.day(for: Date())
        var cal = clock.calendar
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let offsetFromMonday = (weekday + 5) % 7
        let thisMonday = clock.adding(days: -offsetFromMonday, to: today)
        return (0..<columns).map { column in
            let monday = clock.adding(days: -7 * (columns - 1 - column), to: thisMonday)
            return (0..<7).map { i in
                let day = clock.adding(days: i, to: monday)
                return day > today ? nil : day
            }
        }
    }
}
