import AVKit
import SwiftData
import SwiftUI
import GrindCore

struct GalleryView: View {
    @Query(filter: #Predicate<StudySession> { $0.videoFile != nil }, sort: \StudySession.startedAt, order: .reverse)
    private var sessions: [StudySession]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if sessions.isEmpty {
                    ContentUnavailableView("Noch keine Zeitraffer",
                                           systemImage: "play.rectangle.on.rectangle",
                                           description: Text("Jede Session mit Kamera wird hier zu einem kurzen Video."))
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                tile(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .background(Color.black)
            .navigationTitle("Videos")
        }
    }

    private func tile(_ session: StudySession) -> some View {
        Color.clear
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                Thumbnail(url: session.thumbnailURL, symbol: session.subject?.symbol ?? "book.fill", tint: session.subjectColor)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DurationFormat.short(session.activeSeconds))
                        .font(.caption.weight(.bold).monospacedDigit())
                    Text(session.startedAt.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topLeading) {
                Circle().fill(session.subjectColor).frame(width: 8, height: 8).padding(8)
            }
            .clipShape(.rect(cornerRadius: 12))
    }
}

struct SessionDetailView: View {
    @Bindable var session: StudySession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortIndex) private var subjects: [Subject]

    @State private var player: AVPlayer?
    @State private var saveMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let url = session.videoURL {
                Section {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxHeight: 520)
                        .clipShape(.rect(cornerRadius: 16))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .onAppear {
                            if player == nil { player = AVPlayer(url: url) }
                            player?.play()
                        }
                        .onDisappear { player?.pause() }
                }
                Section {
                    Button {
                        Task { await save(url) }
                    } label: {
                        Label(saveMessage ?? "In Fotos sichern", systemImage: "square.and.arrow.down")
                    }
                    ShareLink(item: url) {
                        Label("Video teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("Session") {
                LabeledContent("Gelernt", value: DurationFormat.short(session.activeSeconds))
                LabeledContent("Start", value: session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                LabeledContent("Ende", value: session.endedAt.formatted(.dateTime.hour().minute()))
                if session.pausedSeconds >= 1 {
                    LabeledContent("Pausiert", value: DurationFormat.short(session.pausedSeconds))
                }
                LabeledContent("Unterbrechungen", value: "\(session.interruptions)")
                LabeledContent("Modus", value: session.mode == .timer
                               ? "Timer · \(DurationFormat.short(session.targetSeconds))" : "Stoppuhr")
                if session.endReason != .manual {
                    LabeledContent("Ende", value: session.endReason.label)
                }
            }

            Section("Fach") {
                Picker("Fach", selection: Binding(
                    get: { session.subject?.id },
                    set: { id in
                        session.subject = subjects.first { $0.id == id }
                        try? context.save()
                        SnapshotService.refresh(context)
                    })) {
                    Text("Ohne Fach").tag(UUID?.none)
                    ForEach(subjects) { s in
                        Label(s.name, systemImage: s.symbol).tag(Optional(s.id))
                    }
                }
            }

            Section("Notiz") {
                TextField("Was hast du geschafft?", text: $session.note, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                if session.videoURL != nil {
                    Button("Nur Video löschen", systemImage: "film.stack", role: .destructive) {
                        player?.pause()
                        player = nil
                        session.deleteMedia()
                        try? context.save()
                    }
                }
                Button("Session löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(session.subjectName)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if !session.isDeleted { try? context.save() }
        }
        .confirmationDialog("Session löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                player?.pause()
                player = nil
                let doomed = session
                let ctx = context
                dismiss()
                // Delete after the pop animation so no view reads a detached model.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    doomed.deleteMedia()
                    ctx.delete(doomed)
                    try? ctx.save()
                    SnapshotService.refresh(ctx)
                }
            }
        } message: {
            Text("Die Lernzeit zählt danach nicht mehr für deinen Streak.")
        }
    }

    private func save(_ url: URL) async {
        do {
            try await PhotoSaver.saveVideo(url)
            saveMessage = "In Fotos gesichert ✓"
            Haptics.success()
        } catch {
            saveMessage = "Kein Zugriff auf Fotos"
            Haptics.warning()
        }
    }
}
