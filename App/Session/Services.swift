import Foundation
import Photos
import SwiftData
import UIKit
import WidgetKit
import GrindCore

@MainActor
enum SnapshotService {
    static func refresh(_ context: ModelContext?) {
        guard let context, let sessions = try? context.fetch(FetchDescriptor<StudySession>()) else { return }
        let clock = Pref.clock
        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            goalSeconds: Pref.goalSeconds,
            dayStartHour: clock.dayStartHour,
            totals: Aggregation.dailyTotals(sessions.map(\.sample), clock: clock)
        )
        AppGroup.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Screen brightness control. iOS keeps an app-set brightness until the device locks,
/// so we always restore the user's value when leaving the session screen or the app.
@MainActor
enum Brightness {
    private static var saved: CGFloat?

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    static func set(_ level: CGFloat) {
        guard let screen else { return }
        if saved == nil { saved = screen.brightness }
        screen.brightness = level
    }

    static func restore() {
        guard let saved, let screen else { return }
        screen.brightness = saved
        self.saved = nil
    }
}

enum PhotoSaver {
    enum Failure: Error { case denied, failed }

    static func saveVideo(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

@MainActor
enum SubjectSeeder {
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: Pref.subjectsSeeded) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Subject>())) ?? 0
        if existing == 0 {
            let defaults: [(String, String, String)] = [
                ("Lineare Algebra", "5B8CFF", "function"),
                ("LDS", "A78BFA", "sum"),
                ("DSA", "34D399", "chevron.left.forwardslash.chevron.right"),
                ("Sonstiges", "94A3B8", "book.fill")
            ]
            for (index, item) in defaults.enumerated() {
                context.insert(Subject(name: item.0, colorHex: item.1, symbol: item.2, sortIndex: index))
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: Pref.subjectsSeeded)
    }
}
