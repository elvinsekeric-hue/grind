import SwiftData
import SwiftUI

struct SessionSetupView: View {
    @Environment(SessionController.self) private var controller
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortIndex) private var subjects: [Subject]

    @AppStorage(Pref.defaultCamera) private var cameraRaw = CameraPosition.front.rawValue
    @AppStorage(Pref.defaultTimerMinutes) private var timerMinutes = 50
    @AppStorage(Pref.defaultMode) private var modeRaw = SessionMode.timer.rawValue
    @AppStorage(Pref.recordVideo) private var recordVideo = true
    @AppStorage(Pref.lastSubjectID) private var lastSubjectID = ""

    let close: () -> Void

    @State private var countdown: Int?
    @State private var cameraDenied = false
    @State private var showFocusGuide = false
    @State private var customMinutes = false

    private var camera: CameraPosition { CameraPosition(rawValue: cameraRaw) ?? .front }
    private var mode: SessionMode { SessionMode(rawValue: modeRaw) ?? .timer }
    private var selectedSubject: Subject? {
        subjects.first { $0.id.uuidString == lastSubjectID } ?? subjects.first
    }
    private let presets = [25, 50, 90]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if recordVideo && !cameraDenied {
                CameraPreview(session: controller.recorder.session, generation: controller.cameraGeneration)
                    .ignoresSafeArea()
                    .overlay(LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.85)],
                                            startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                    .transition(.opacity)
            } else {
                noCameraBackdrop
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
            }

            if let countdown {
                countdownOverlay(countdown)
            }
        }
        .statusBarHidden(countdown != nil)
        .task(id: "\(cameraRaw)-\(recordVideo)") { await setupCamera() }
        .onDisappear { controller.releaseCamera() }
        .sheet(isPresented: $showFocusGuide) {
            NavigationStack { FocusGuideView() }
        }
    }

    // MARK: Parts

    private var noCameraBackdrop: some View {
        VStack(spacing: 14) {
            Image(systemName: cameraDenied ? "video.slash.fill" : "eye.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(cameraDenied ? "Kein Kamerazugriff" : "Ohne Zeitraffer")
                .font(.headline)
            if cameraDenied {
                Text("Die Session läuft trotzdem, nur ohne Video.\nErlaube den Zugriff in den Einstellungen.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.bottom, 260)
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            Spacer()

            Button {
                withAnimation { recordVideo.toggle() }
            } label: {
                Label(recordVideo ? "Zeitraffer an" : "Zeitraffer aus",
                      systemImage: recordVideo ? "record.circle" : "record.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(recordVideo ? Color.red : Color.secondary)
            }
            .buttonStyle(.glass)

            if recordVideo && !cameraDenied {
                Button {
                    Haptics.tap()
                    cameraRaw = camera.toggled.rawValue
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            subjectPicker
            modePicker
            if mode == .timer { durationPicker }

            Button(action: beginCountdown) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                    Text("Los geht's")
                }
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.ember)
            .disabled(countdown != nil)

            Button { showFocusGuide = true } label: {
                Label("Display wird schwarz, Sperrtaste nicht drücken. Fokus einrichten", systemImage: "moon.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fach").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(subjects) { subject in
                        let selected = subject.id == selectedSubject?.id
                        Button {
                            Haptics.tap()
                            lastSubjectID = subject.id.uuidString
                        } label: {
                            Label(subject.name, systemImage: subject.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(selected ? subject.color.opacity(0.9) : Color.white.opacity(0.08), in: .capsule)
                                .foregroundStyle(selected ? Color.black : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var modePicker: some View {
        Picker("Modus", selection: $modeRaw) {
            ForEach(SessionMode.allCases) { m in
                Label(m.label, systemImage: m.symbol).tag(m.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { minutes in
                    chip("\(minutes) min", selected: !customMinutes && timerMinutes == minutes) {
                        customMinutes = false
                        timerMinutes = minutes
                    }
                }
                chip(customMinutes || !presets.contains(timerMinutes) ? "\(timerMinutes) min" : "Eigene",
                     selected: customMinutes || !presets.contains(timerMinutes)) {
                    customMinutes = true
                }
            }
            if customMinutes || !presets.contains(timerMinutes) {
                Stepper(value: $timerMinutes, in: 5...480, step: 5) {
                    Text("Dauer: \(timerMinutes) min").font(.subheadline.monospacedDigit())
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? Color.ember : Color.white.opacity(0.08), in: .capsule)
                .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func countdownOverlay(_ value: Int) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 160, weight: .heavy, design: .rounded))
                .foregroundStyle(.emberGradient)
                .contentTransition(.numericText(countsDown: true))
                .shadow(color: .ember.opacity(0.6), radius: 30)
        }
        .onTapGesture { countdown = nil }
        .transition(.opacity)
    }

    // MARK: Actions

    private func setupCamera() async {
        guard recordVideo else {
            controller.releaseCamera()
            return
        }
        if TimelapseRecorder.isDenied {
            cameraDenied = true
            return
        }
        await controller.prepareCamera(camera)
        cameraDenied = !TimelapseRecorder.isAuthorized
    }

    private func beginCountdown() {
        SessionController.requestNotificationPermission()
        Haptics.heavy()
        withAnimation { countdown = 3 }
        Task { @MainActor in
            for next in [2, 1] {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard countdown != nil else { return }
                Haptics.tap()
                withAnimation(.snappy) { countdown = next }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard countdown != nil else { return }
            countdown = nil
            let config = SessionConfig(
                mode: mode,
                targetSeconds: Double(timerMinutes * 60),
                camera: camera,
                recordVideo: recordVideo && !cameraDenied,
                subjectID: selectedSubject?.id
            )
            controller.start(config)
        }
    }
}
