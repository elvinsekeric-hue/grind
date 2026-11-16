import SwiftData
import SwiftUI
import GrindCore

struct SessionSummaryView: View {
    @Environment(SessionController.self) private var controller
    @Environment(\.modelContext) private var context
    let done: () -> Void

    @State private var session: StudySession?
    @State private var note = ""
    @State private var appeared = false
    @State private var saveState: SaveState = .idle
    @State private var confirmDiscard = false

    enum SaveState { case idle, saving, saved, failed }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = session?.videoURL {
                LoopingVideoView(url: url)
                    .ignoresSafeArea()
                    .opacity(0.55)
                    .blur(radius: appeared ? 0 : 20)
                LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.4), .black.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                RadialGradient(colors: [Color.ember.opacity(0.25), .black], center: .top, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()
            }

            if let result = controller.result {
                content(result)
            }
        }
        .onAppear {
            loadSession()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.15)) { appeared = true }
            if controller.result?.goalReachedNow == true { Haptics.success() }
        }
        .confirmationDialog("Session verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                if let id = controller.result?.sessionID { controller.discard(id) }
                done()
            }
        } message: {
            Text("Zeit und Video werden gelöscht. Dein Streak wird neu berechnet.")
        }
    }

    private func content(_ result: SessionResult) -> some View {
        VStack(spacing: 22) {
            HStack {
                Menu {
                    Button("Session verwerfen", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Spacer()
            }
            .padding(.horizontal, 20)

            Spacer()

            streakBadge(result)

            VStack(spacing: 6) {
                Text(DurationFormat.short(result.activeSeconds))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                Text(headline(result))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            statsRow(result)

            Spacer()

            actions
        }
        .padding(.bottom, 12)
    }

    private func headline(_ result: SessionResult) -> String {
        if result.reason == .abandoned || result.reason == .recovered { return result.reason.label }
        if result.goalReachedNow { return "Tagesziel geschafft. Streak gesichert." }
        if result.after.todayDone { return "Heute schon \(DurationFormat.short(result.after.todaySeconds)) gelernt" }
        return "Noch \(DurationFormat.short(result.after.remainingSeconds)) bis zum Tagesziel"
    }

    private func streakBadge(_ result: SessionResult) -> some View {
        let lit = result.after.todayDone
        return VStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .foregroundStyle(lit ? AnyShapeStyle(.emberGradient) : AnyShapeStyle(Color.white.opacity(0.25)))
                .symbolEffect(.bounce, value: appeared)
                .shadow(color: lit ? .ember.opacity(0.7) : .clear, radius: 24)
            Text("\(appeared ? result.after.current : result.before.current)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(result.after.current == 1 ? "Tag Streak" : "Tage Streak")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func statsRow(_ result: SessionResult) -> some View {
        HStack(spacing: 10) {
            stat(session?.subjectName ?? "Ohne Fach", "Fach", tint: session?.subjectColor ?? .gray)
            stat("\(session?.interruptions ?? 0)", "Unterbrechungen", tint: (session?.interruptions ?? 0) == 0 ? .green : .yellow)
            stat(DurationFormat.short(result.after.todaySeconds), "Heute", tint: .ember)
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            TextField("Notiz (optional): Was hast du geschafft?", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .onSubmit(saveNote)

            if let url = session?.videoURL {
                HStack(spacing: 12) {
                    Button {
                        Task { await saveToPhotos(url) }
                    } label: {
                        Label(saveLabel, systemImage: saveState == .saved ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .disabled(saveState == .saving || saveState == .saved)

                    ShareLink(item: url) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }

            Button {
                saveNote()
                done()
            } label: {
                Text("Fertig")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.ember)
        }
        .padding(.horizontal, 16)
    }

    private var saveLabel: String {
        switch saveState {
        case .idle: return "In Fotos"
        case .saving: return "Speichere…"
        case .saved: return "Gesichert"
        case .failed: return "Kein Zugriff"
        }
    }

    private func loadSession() {
        guard let id = controller.result?.sessionID else { return }
        session = try? context.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.id == id })).first
        note = session?.note ?? ""
    }

    private func saveNote() {
        guard let session, session.note != note else { return }
        session.note = note
        try? context.save()
    }

    private func saveToPhotos(_ url: URL) async {
        saveState = .saving
        do {
            try await PhotoSaver.saveVideo(url)
            saveState = .saved
            Haptics.success()
        } catch {
            saveState = .failed
            Haptics.warning()
        }
    }
}
