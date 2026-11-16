import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import GrindCore

struct SessionConfig: Codable, Equatable {
    var mode: SessionMode
    var targetSeconds: Double
    var camera: CameraPosition
    var recordVideo: Bool
    var subjectID: UUID?
}

/// Persisted on every state change so a killed app can recover the session.
struct ActiveState: Codable, Equatable {
    var id: UUID
    var config: SessionConfig
    var startedAt: Date
    var accumulated: Double = 0
    var segmentStart: Date?
    var manualPauseSince: Date?
    var awaySince: Date?
    var pausedSeconds: Double = 0
    var interruptions: Int = 0
    var heartbeat: Date

    func active(at now: Date) -> Double {
        accumulated + (segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

struct SessionResult: Equatable {
    var sessionID: UUID
    var activeSeconds: Double
    var before: StreakSummary
    var after: StreakSummary
    var reason: EndReason

    var goalReachedNow: Bool { !before.todayDone && after.todayDone }
}

struct AwayNotice: Equatable, Identifiable {
    let id = UUID()
    let seconds: Double
}

@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finishing(Double)
        case summary
    }

    static let awayGrace: Double = 120

    private(set) var phase: Phase = .idle
    private(set) var state: ActiveState?
    private(set) var now = Date()
    private(set) var frameCount = 0
    private(set) var result: SessionResult?
    var awayNotice: AwayNotice?

    let recorder = TimelapseRecorder()
    private var context: ModelContext?
    private var ticker: Task<Void, Never>?
    private var lastPersist = Date.distantPast

    init() {
        recorder.onFrameCount = { [weak self] count in self?.frameCount = count }
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    var isActive: Bool { phase != .idle }

    var activeSeconds: Double { state?.active(at: now) ?? 0 }

    var remainingSeconds: Double? {
        guard let s = state, s.config.mode == .timer else { return nil }
        return max(0, s.config.targetSeconds - activeSeconds)
    }

    var progress: Double? {
        guard let s = state, s.config.mode == .timer, s.config.targetSeconds > 0 else { return nil }
        return min(1, activeSeconds / s.config.targetSeconds)
    }

    var subject: Subject? {
        guard let id = state?.config.subjectID, let context else { return nil }
        return try? context.fetch(FetchDescriptor<Subject>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: Camera for setup screen

    func prepareCamera(_ position: CameraPosition) async {
        guard await TimelapseRecorder.requestAccess() else { return }
        await recorder.configure(position: position)
        recorder.setFrameRate(30)
        recorder.startRunning()
    }

    func releaseCamera() {
        guard phase == .idle else { return }
        recorder.stopRunning()
    }

    // MARK: Lifecycle

    func start(_ config: SessionConfig) {
        guard phase == .idle else { return }
        Storage.clearActive()
        recorder.resetFrames()
        frameCount = 0
        result = nil
        let start = Date()
        now = start
        state = ActiveState(id: UUID(), config: config, startedAt: start, segmentStart: start, heartbeat: start)
        persist(force: true)

        if config.recordVideo && TimelapseRecorder.isAuthorized {
            recorder.setFrameRate(5)
            recorder.startRunning()
            recorder.beginCapturing()
        } else {
            recorder.stopRunning()
        }
        UIApplication.shared.isIdleTimerDisabled = true
        phase = .running
        startTicker()
        Haptics.success()
    }

    func pause() {
        guard phase == .running, var s = state else { return }
        let t = Date()
        s.accumulated = s.active(at: t)
        s.segmentStart = nil
        s.manualPauseSince = t
        state = s
        recorder.pauseCapturing()
        phase = .paused
        persist(force: true)
        Haptics.tap()
    }

    func resume() {
        guard phase == .paused, var s = state else { return }
        let t = Date()
        if let since = s.manualPauseSince { s.pausedSeconds += t.timeIntervalSince(since) }
        s.manualPauseSince = nil
        s.segmentStart = t
        state = s
        if s.config.recordVideo { recorder.beginCapturing() }
        phase = .running
        persist(force: true)
        Haptics.tap()
    }

    func stop() {
        Task { await finish(reason: .manual, endAt: Date()) }
    }

    func reset() {
        phase = .idle
        state = nil
        result = nil
        frameCount = 0
    }

    // MARK: Leaving the app

    func didEnterBackground() {
        guard phase == .running || phase == .paused, var s = state, s.awaySince == nil else { return }
        let t = Date()
        if s.segmentStart != nil {
            s.accumulated = s.active(at: t)
            s.segmentStart = nil
        }
        s.awaySince = t
        state = s
        recorder.pauseCapturing()
        persist(force: true)
        scheduleAwayNotifications()
    }

    func didBecomeActive() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.awayIDs)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Self.awayIDs)
        guard var s = state, let away = s.awaySince, phase == .running || phase == .paused else { return }
        let t = Date()
        let gone = t.timeIntervalSince(away)
        now = t
        if gone > Self.awayGrace {
            Task { await finish(reason: .abandoned, endAt: away) }
            return
        }
        s.awaySince = nil
        s.interruptions += 1
        if s.manualPauseSince == nil {
            s.pausedSeconds += gone
            s.segmentStart = t
            if s.config.recordVideo { recorder.beginCapturing() }
            phase = .running
        }
        state = s
        persist(force: true)
        awayNotice = AwayNotice(seconds: gone)
        Haptics.warning()
    }

    private static let awayIDs = ["grind.away.now", "grind.away.last"]

    private func scheduleAwayNotifications() {
        let center = UNUserNotificationCenter.current()
        let first = UNMutableNotificationContent()
        first.title = "Session pausiert"
        first.body = "Komm in 2 Minuten zurück, sonst endet deine Session."
        first.sound = .default
        let last = UNMutableNotificationContent()
        last.title = "Noch 30 Sekunden"
        last.body = "Zurück zu Grind, sonst ist die Session vorbei."
        last.sound = .default
        first.interruptionLevel = .timeSensitive
        last.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: Self.awayIDs[0], content: first,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
        center.add(UNNotificationRequest(identifier: Self.awayIDs[1], content: last,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.awayGrace - 30, repeats: false)))
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: Ticker

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard phase == .running || phase == .paused else { return }
        now = Date()
        if phase == .running, let remaining = remainingSeconds, remaining <= 0 {
            Task { await finish(reason: .completed, endAt: Date()) }
            return
        }
        if phase == .running { persist(force: false) }
    }

    // MARK: Persistence

    private func persist(force: Bool) {
        guard var s = state else { return }
        let t = Date()
        guard force || t.timeIntervalSince(lastPersist) > 10 else { return }
        s.heartbeat = t
        state = s
        lastPersist = t
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: Storage.stateURL, options: .atomic)
        }
    }

    /// Finalizes a session that was interrupted by the app being killed.
    func recoverIfNeeded() async {
        guard phase == .idle,
              let data = try? Data(contentsOf: Storage.stateURL),
              let saved = try? JSONDecoder().decode(ActiveState.self, from: data)
        else {
            Storage.clearActive()
            return
        }
        state = saved
        let end = saved.awaySince ?? saved.manualPauseSince ?? saved.heartbeat
        await finish(reason: .recovered, endAt: end)
    }

    // MARK: Finish

    func finish(reason: EndReason, endAt: Date) async {
        guard var s = state else { return }
        if case .finishing = phase { return }
        if phase == .summary { return }

        ticker?.cancel()
        if let seg = s.segmentStart {
            s.accumulated += max(0, endAt.timeIntervalSince(seg))
            s.segmentStart = nil
        }
        if let since = s.manualPauseSince {
            s.pausedSeconds += max(0, endAt.timeIntervalSince(since))
            s.manualPauseSince = nil
        }
        state = s
        now = endAt
        recorder.pauseCapturing()
        await recorder.drain()
        recorder.stopRunning()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .finishing(0)
        if reason == .completed { Haptics.success() }

        let before = currentSummary()

        // Compose the timelapse.
        var videoName: String?
        var thumbName: String?
        var videoSeconds = 0.0
        let frames = Storage.frameURLs()
        if !frames.isEmpty {
            let video = Storage.videosDir.appendingPathComponent("\(s.id.uuidString).mp4")
            let thumb = Storage.videosDir.appendingPathComponent("\(s.id.uuidString).jpg")
            do {
                let composed = try await TimelapseComposer.compose(frames: frames, output: video, thumbnail: thumb) { p in
                    Task { @MainActor [weak self] in
                        if case .finishing = self?.phase { self?.phase = .finishing(p) }
                    }
                }
                videoName = video.lastPathComponent
                thumbName = composed.thumbnailURL?.lastPathComponent
                videoSeconds = composed.duration
            } catch {
                try? FileManager.default.removeItem(at: video)
            }
        }

        // Save.
        let session = StudySession(id: s.id, startedAt: s.startedAt, endedAt: endAt, activeSeconds: s.accumulated)
        session.pausedSeconds = s.pausedSeconds
        session.targetSeconds = s.config.mode == .timer ? s.config.targetSeconds : 0
        session.modeRaw = s.config.mode.rawValue
        session.endReasonRaw = reason.rawValue
        session.cameraRaw = s.config.camera.rawValue
        session.interruptions = s.interruptions
        session.videoFile = videoName
        session.thumbnailFile = thumbName
        session.videoSeconds = videoSeconds
        session.subject = subject
        if let context {
            context.insert(session)
            try? context.save()
        }
        Storage.clearActive()
        SnapshotService.refresh(context)

        result = SessionResult(sessionID: s.id, activeSeconds: s.accumulated, before: before, after: currentSummary(), reason: reason)
        state = nil
        phase = .summary
    }

    func discard(_ sessionID: UUID) {
        guard let context,
              let session = try? context.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.id == sessionID })).first
        else { return }
        session.deleteMedia()
        context.delete(session)
        try? context.save()
        SnapshotService.refresh(context)
    }

    private func currentSummary() -> StreakSummary {
        guard let context, let sessions = try? context.fetch(FetchDescriptor<StudySession>()) else { return .empty }
        let clock = Pref.clock
        let totals = Aggregation.dailyTotals(sessions.map(\.sample), clock: clock)
        return StreakCalculator.summarize(totals: totals, goalSeconds: Pref.goalSeconds, now: Date(), clock: clock)
    }
}
