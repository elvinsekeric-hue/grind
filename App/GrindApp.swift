import SwiftData
import SwiftUI

@main
struct GrindApp: App {
    @State private var controller = SessionController()
    private let container: ModelContainer

    init() {
        Pref.registerDefaults()
        do {
            container = try ModelContainer(for: StudySession.self, Subject.self)
        } catch {
            // Last resort: never crash on launch because of the store.
            container = try! ModelContainer(for: StudySession.self, Subject.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(controller)
                .preferredColorScheme(.dark)
                .tint(.ember)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(SessionController.self) private var controller
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Pref.onboardingDone) private var onboardingDone = false
    @AppStorage(Pref.goalMinutes) private var goalMinutes = 25
    @AppStorage(Pref.dayStartHour) private var dayStartHour = 4

    @State private var showFlow = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Heute", systemImage: "flame.fill", value: 0) {
                HomeView(onStart: { showFlow = true })
            }
            Tab("Statistik", systemImage: "chart.bar.xaxis", value: 1) {
                StatsView()
            }
            Tab("Videos", systemImage: "play.rectangle.on.rectangle.fill", value: 2) {
                GalleryView()
            }
            Tab("Einstellungen", systemImage: "gearshape.fill", value: 3) {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: $showFlow) {
            SessionFlowView(close: { showFlow = false })
                .environment(controller)
        }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingView { onboardingDone = true }
                .interactiveDismissDisabled()
        }
        .onChange(of: controller.phase) { _, phase in
            if phase != .idle { showFlow = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: controller.didEnterBackground()
            case .active:
                controller.didBecomeActive()
                SnapshotService.refresh(context)
            default: break
            }
        }
        .onChange(of: goalMinutes) { SnapshotService.refresh(context) }
        .onChange(of: dayStartHour) { SnapshotService.refresh(context) }
        .onOpenURL { url in
            if url.host == "start", !controller.isActive { showFlow = true }
        }
        .task {
            controller.attach(context)
            SubjectSeeder.seedIfNeeded(context)
            await controller.recoverIfNeeded()
            SnapshotService.refresh(context)
        }
    }
}

struct SessionFlowView: View {
    @Environment(SessionController.self) private var controller
    let close: () -> Void

    var body: some View {
        Group {
            switch controller.phase {
            case .idle:
                SessionSetupView(close: close)
            case .running, .paused:
                ActiveSessionView()
            case .finishing(let progress):
                FinishingView(progress: progress)
            case .summary:
                SessionSummaryView(done: {
                    close()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        controller.reset()
                    }
                })
            }
        }
        .animation(.smooth(duration: 0.45), value: controller.phase)
    }
}
