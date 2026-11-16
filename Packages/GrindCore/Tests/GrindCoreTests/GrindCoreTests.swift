import XCTest
@testable import GrindCore

final class DayClockTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testLateNightCountsForPreviousDay() {
        let clock = DayClock(calendar: calendar, dayStartHour: 4)
        XCTAssertEqual(clock.key(forMoment: date(2026, 11, 17, 1, 30)), "2026-11-16")
        XCTAssertEqual(clock.key(forMoment: date(2026, 11, 17, 4, 0)), "2026-11-17")
        XCTAssertEqual(clock.key(forMoment: date(2026, 11, 17, 23, 59)), "2026-11-17")
    }

    func testMidnightStart() {
        let clock = DayClock(calendar: calendar, dayStartHour: 0)
        XCTAssertEqual(clock.key(forMoment: date(2026, 11, 17, 0, 1)), "2026-11-17")
    }

    func testNextBoundary() {
        let clock = DayClock(calendar: calendar, dayStartHour: 4)
        XCTAssertEqual(clock.nextBoundary(after: date(2026, 11, 17, 2, 0)), date(2026, 11, 17, 4, 0))
        XCTAssertEqual(clock.nextBoundary(after: date(2026, 11, 17, 10, 0)), date(2026, 11, 18, 4, 0))
    }

    func testKeyRoundTripAcrossDST() {
        let clock = DayClock(calendar: calendar, dayStartHour: 4)
        let day = clock.date(fromKey: "2026-03-29")!
        XCTAssertEqual(clock.key(for: day), "2026-03-29")
        XCTAssertEqual(clock.key(for: clock.adding(days: 1, to: day)), "2026-03-30")
        XCTAssertEqual(clock.days(endingAt: day, count: 3).map(clock.key(for:)), ["2026-03-27", "2026-03-28", "2026-03-29"])
    }
}

final class StreakTests: XCTestCase {
    var clock: DayClock = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return DayClock(calendar: c, dayStartHour: 4)
    }()

    func now(_ key: String, hour: Int = 15) -> Date {
        clock.date(fromKey: key)!.addingTimeInterval(Double(hour) * 3600)
    }

    func testStreakIncludesTodayWhenDone() {
        let totals = ["2026-11-14": 1800.0, "2026-11-15": 1500, "2026-11-16": 1600]
        let s = StreakCalculator.summarize(totals: totals, goalSeconds: 1500, now: now("2026-11-16"), clock: clock)
        XCTAssertEqual(s.current, 3)
        XCTAssertTrue(s.todayDone)
    }

    func testOpenTodayDoesNotBreakStreak() {
        let totals = ["2026-11-14": 1800.0, "2026-11-15": 1500, "2026-11-16": 600]
        let s = StreakCalculator.summarize(totals: totals, goalSeconds: 1500, now: now("2026-11-16"), clock: clock)
        XCTAssertEqual(s.current, 2)
        XCTAssertFalse(s.todayDone)
        XCTAssertEqual(s.remainingSeconds, 900)
    }

    func testMissedDayBreaksStreak() {
        let totals = ["2026-11-12": 1800.0, "2026-11-13": 1800, "2026-11-15": 1500]
        let s = StreakCalculator.summarize(totals: totals, goalSeconds: 1500, now: now("2026-11-16"), clock: clock)
        XCTAssertEqual(s.current, 1)
        XCTAssertEqual(s.longest, 2)
    }

    func testBelowGoalDoesNotCount() {
        let totals = ["2026-11-15": 1499.0]
        let s = StreakCalculator.summarize(totals: totals, goalSeconds: 1500, now: now("2026-11-16"), clock: clock)
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.longest, 0)
    }

    func testLateNightSessionKeepsYesterdayAlive() {
        // Session at 01:30 on the 17th belongs to the 16th.
        let start = now("2026-11-17", hour: 1).addingTimeInterval(1800)
        let samples = [SessionSample(start: start, end: start.addingTimeInterval(1600), activeSeconds: 1600)]
        let totals = Aggregation.dailyTotals(samples, clock: clock)
        XCTAssertEqual(totals["2026-11-16"], 1600)
    }

    func testLongestAcrossMonthBoundary() {
        let totals = ["2026-10-30": 2000.0, "2026-10-31": 2000, "2026-11-01": 2000, "2026-11-02": 2000]
        let s = StreakCalculator.summarize(totals: totals, goalSeconds: 1500, now: now("2026-11-10"), clock: clock)
        XCTAssertEqual(s.longest, 4)
        XCTAssertEqual(s.current, 0)
    }

    func testHourHistogramSpreadsAcrossHours() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 30))!
        let sample = SessionSample(start: start, end: start.addingTimeInterval(3600), activeSeconds: 3600)
        let h = Aggregation.hourHistogram([sample], calendar: cal)
        XCTAssertEqual(h[9], 1800, accuracy: 0.5)
        XCTAssertEqual(h[10], 1800, accuracy: 0.5)
        XCTAssertEqual(h.reduce(0, +), 3600, accuracy: 0.5)
    }
}

final class FrameScheduleTests: XCTestCase {
    func testDecimationKeepsBoundedFramesAndDoublesInterval() {
        var schedule = FrameSchedule(baseInterval: 0.5, maxFrames: 100)
        var onDisk = Set<Int>()
        for _ in 0..<1000 {
            let (id, dropped) = schedule.appendFrame()
            onDisk.insert(id)
            dropped.forEach { onDisk.remove($0) }
            XCTAssertLessThan(onDisk.count, 100)
        }
        XCTAssertEqual(Set(schedule.kept), onDisk)
        XCTAssertEqual(schedule.kept, schedule.kept.sorted())
        XCTAssertGreaterThan(schedule.interval, 0.5)
    }

    func testFramesStayRoughlyEvenInTime() {
        // Simulate 3 hours of camera frames arriving 5x per second.
        var schedule = FrameSchedule(baseInterval: 0.5, maxFrames: 200)
        var times: [Int: Double] = [:]
        var last = -Double.infinity
        var t = 0.0
        while t < 3 * 3600 {
            if schedule.shouldCapture(secondsSinceLast: t - last) {
                last = t
                times[schedule.appendFrame().id] = t
            }
            t += 0.2
        }
        let stamps = schedule.kept.map { times[$0]! }
        let gaps = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        XCTAssertGreaterThanOrEqual(schedule.kept.count, 100)
        XCTAssertLessThan(stamps.first!, 1)
        XCTAssertGreaterThan(stamps.last!, 3 * 3600 - 2 * schedule.interval)
        // No gap is more than ~2x the typical gap.
        let median = gaps.sorted()[gaps.count / 2]
        XCTAssertLessThanOrEqual(gaps.max()!, median * 2.2)
    }

    func testPlaybackFPS() {
        XCTAssertEqual(FrameSchedule.playbackFPS(frameCount: 10), 24)
        XCTAssertEqual(FrameSchedule.playbackFPS(frameCount: 1350), 30)
        XCTAssertEqual(FrameSchedule.playbackFPS(frameCount: 5000), 60)
    }

    func testCodableRoundTrip() throws {
        var schedule = FrameSchedule(baseInterval: 0.5, maxFrames: 10)
        for _ in 0..<15 { _ = schedule.appendFrame() }
        let data = try JSONEncoder().encode(schedule)
        XCTAssertEqual(try JSONDecoder().decode(FrameSchedule.self, from: data), schedule)
    }
}

final class FormatTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(DurationFormat.short(45), "45 s")
        XCTAssertEqual(DurationFormat.short(25 * 60), "25 min")
        XCTAssertEqual(DurationFormat.short(65 * 60), "1 h 05 min")
        XCTAssertEqual(DurationFormat.short(120 * 60), "2 h")
    }

    func testClock() {
        XCTAssertEqual(DurationFormat.clock(63), "01:03")
        XCTAssertEqual(DurationFormat.clock(3723), "1:02:03")
    }

    func testHours() {
        XCTAssertEqual(DurationFormat.hours(30 * 60), "30 min")
        XCTAssertEqual(DurationFormat.hours(4.5 * 3600), "4,5 h")
        XCTAssertEqual(DurationFormat.hours(2 * 3600), "2 h")
    }

    func testSnapshotRoundTrip() throws {
        let snap = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_800_000_000), goalSeconds: 1500, dayStartHour: 4, totals: ["2026-11-16": 1600])
        XCTAssertEqual(try WidgetSnapshot.decode(snap.encoded()), snap)
    }
}
