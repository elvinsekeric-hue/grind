import SwiftUI
import GrindCore

/// The black screen. Tapping shows a dim HUD for a few seconds.
struct ActiveSessionView: View {
    @Environment(SessionController.self) private var controller
    @Environment(\.scenePhase) private var scenePhase

    @State private var hudVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var holdProgress: CGFloat = 0
    @State private var holding = false
    @State private var recPulse = false

    private var isPaused: Bool { controller.phase == .paused }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hudVisible || isPaused {
                hud
                    .transition(.opacity)
            }

            if let notice = controller.awayNotice {
                awayBanner(notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showHUD() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            showHUD()
            recPulse = true
            applyBrightness()
        }
        .onDisappear {
            hideTask?.cancel()
            Brightness.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { applyBrightness() } else { Brightness.restore() }
        }
        .onChange(of: controller.phase) { applyBrightness() }
        .onChange(of: hudVisible) { applyBrightness() }
        .onChange(of: controller.awayNotice) { _, notice in
            guard notice != nil else { return }
            showHUD()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                withAnimation { controller.awayNotice = nil }
            }
        }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let subject = controller.subject {
                    Label(subject.name, systemImage: subject.symbol)
                        .foregroundStyle(subject.color)
                }
                Spacer()
                if controller.state?.config.recordVideo == true {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPaused ? Color.gray : Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(recPulse && !isPaused ? 1 : 0.35)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: recPulse)
                        Text(isPaused ? "PAUSE" : "REC · \(controller.frameCount)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer()

            clock

            Spacer()

            controls
                .padding(.bottom, 40)
        }
    }

    private var clock: some View {
        ZStack {
            if let progress = controller.progress {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.ember.opacity(0.7), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
            }
            VStack(spacing: 6) {
                Text(DurationFormat.clock(controller.remainingSeconds ?? controller.activeSeconds))
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(isPaused ? "Pausiert, Zeit läuft nicht" : (controller.remainingSeconds != nil ? "verbleibend" : "gelernt"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, height: 280)
    }

    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 22) {
                Button {
                    if isPaused { controller.resume() } else { controller.pause() }
                    showHUD()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 72, height: 72)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                stopButton
            }
            Text(isPaused ? "Tippe ▶ zum Weitermachen" : "Halten zum Beenden · Tippen blendet ein")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var stopButton: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.ember, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "stop.fill")
                .font(.title2)
                .foregroundStyle(holding ? Color.ember : Color.white)
        }
        .frame(width: 72, height: 72)
        .scaleEffect(holding ? 1.08 : 1)
        .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 40) {
            holding = false
            Haptics.heavy()
            controller.stop()
        } onPressingChanged: { pressing in
            holding = pressing
            hideTask?.cancel()
            if pressing {
                Haptics.tap()
                withAnimation(.linear(duration: 1.2)) { holdProgress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
                scheduleHide()
            }
        }
        .accessibilityLabel("Session beenden")
    }

    private func awayBanner(_ notice: AwayNotice) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Du warst \(DurationFormat.short(notice.seconds)) weg")
                        .font(.subheadline.weight(.semibold))
                    Text("Diese Zeit zählt nicht. Nach 2 Minuten außerhalb endet die Session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 16)
            .padding(.top, 54)
            Spacer()
        }
    }

    // MARK: Behaviour

    private func showHUD() {
        withAnimation(.easeOut(duration: 0.25)) { hudVisible = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, !holding else { return }
            withAnimation(.easeIn(duration: 0.8)) { hudVisible = false }
        }
    }

    private func applyBrightness() {
        guard scenePhase == .active else { return }
        switch controller.phase {
        case .running: Brightness.set(hudVisible ? 0.25 : 0)
        case .paused: Brightness.set(0.35)
        default: Brightness.restore()
        }
    }
}

struct FinishingView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(.emberGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: progress)
                    Text("\(Int(progress * 100)) %")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 140, height: 140)
                Text("Zeitraffer wird erstellt")
                    .font(.headline)
                Text("Gleich fertig. Lass die App kurz offen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { Brightness.restore() }
    }
}
