import Foundation
import SwiftData
import SwiftUI
import GrindCore

@Model
final class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "FF6B1A"
    var symbol: String = "book.fill"
    var sortIndex: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \StudySession.subject)
    var sessions: [StudySession] = []

    init(name: String, colorHex: String, symbol: String, sortIndex: Int) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    var color: Color { Color(hex: colorHex) }

    static let palette = ["FF6B1A", "FF3B5C", "FFC233", "34D399", "22C3EE", "5B8CFF", "A78BFA", "F472B6", "94A3B8"]
    static let symbols = [
        "book.fill", "function", "sum", "x.squareroot", "chevron.left.forwardslash.chevron.right",
        "cpu.fill", "brain.head.profile", "atom", "flask.fill", "globe.europe.africa.fill",
        "character.book.closed.fill", "pencil.and.ruler.fill", "chart.xyaxis.line", "graduationcap.fill", "laptopcomputer", "star.fill"
    ]
}

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case timer, stopwatch
    var id: String { rawValue }
    var label: String { self == .timer ? "Timer" : "Stoppuhr" }
    var symbol: String { self == .timer ? "timer" : "stopwatch" }
}

enum EndReason: String, Codable {
    case completed, manual, abandoned, recovered

    var label: String {
        switch self {
        case .completed: return "Ziel erreicht"
        case .manual: return "Beendet"
        case .abandoned: return "Beendet, weil du länger als 2 Minuten weg warst"
        case .recovered: return "Wiederhergestellt nach unerwartetem Ende"
        }
    }
}

enum CameraPosition: String, Codable, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
    var label: String { self == .front ? "Front" : "Rück" }
    var toggled: CameraPosition { self == .front ? .back : .front }
}

@Model
final class StudySession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var activeSeconds: Double = 0
    var pausedSeconds: Double = 0
    var targetSeconds: Double = 0
    var modeRaw: String = SessionMode.stopwatch.rawValue
    var endReasonRaw: String = EndReason.manual.rawValue
    var cameraRaw: String = CameraPosition.front.rawValue
    var interruptions: Int = 0
    var videoFile: String?
    var thumbnailFile: String?
    var videoSeconds: Double = 0
    var note: String = ""
    var subject: Subject?

    init(id: UUID, startedAt: Date, endedAt: Date, activeSeconds: Double) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
    }

    var mode: SessionMode { SessionMode(rawValue: modeRaw) ?? .stopwatch }
    var endReason: EndReason { EndReason(rawValue: endReasonRaw) ?? .manual }

    var videoURL: URL? {
        guard let videoFile else { return nil }
        let url = Storage.videosDir.appendingPathComponent(videoFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var thumbnailURL: URL? {
        guard let thumbnailFile else { return nil }
        return Storage.videosDir.appendingPathComponent(thumbnailFile)
    }

    var sample: SessionSample {
        SessionSample(start: startedAt, end: endedAt, activeSeconds: activeSeconds, subjectID: subject?.id)
    }

    var subjectName: String { subject?.name ?? "Ohne Fach" }
    var subjectColor: Color { subject?.color ?? .gray }

    func deleteMedia() {
        for url in [videoURL, thumbnailURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        videoFile = nil
        thumbnailFile = nil
    }
}

enum Pref {
    static let goalMinutes = "goalMinutes"
    static let dayStartHour = "dayStartHour"
    static let defaultCamera = "defaultCamera"
    static let defaultTimerMinutes = "defaultTimerMinutes"
    static let defaultMode = "defaultMode"
    static let recordVideo = "recordVideo"
    static let lastSubjectID = "lastSubjectID"
    static let onboardingDone = "onboardingDone"
    static let subjectsSeeded = "subjectsSeeded"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            goalMinutes: 25,
            dayStartHour: 4,
            defaultCamera: CameraPosition.front.rawValue,
            defaultTimerMinutes: 50,
            defaultMode: SessionMode.timer.rawValue,
            recordVideo: true
        ])
    }

    static var clock: DayClock {
        DayClock(dayStartHour: UserDefaults.standard.integer(forKey: dayStartHour))
    }

    static var goalSeconds: Double {
        Double(max(5, UserDefaults.standard.integer(forKey: goalMinutes)) * 60)
    }
}

enum Storage {
    private static func dir(_ base: FileManager.SearchPathDirectory, _ name: String) -> URL {
        let root = FileManager.default.urls(for: base, in: .userDomainMask)[0]
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var videosDir: URL { dir(.documentDirectory, "Timelapses") }
    static var activeDir: URL { dir(.applicationSupportDirectory, "ActiveSession") }

    static var framesDir: URL {
        let url = activeDir.appendingPathComponent("frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var stateURL: URL { activeDir.appendingPathComponent("state.json") }

    static func frameURLs() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func clearActive() {
        try? FileManager.default.removeItem(at: activeDir)
    }

    static func videosBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
