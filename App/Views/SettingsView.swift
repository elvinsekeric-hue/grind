import SwiftData
import SwiftUI
import GrindCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.goalMinutes) private var goalMinutes = 25
    @AppStorage(Pref.dayStartHour) private var dayStartHour = 4
    @AppStorage(Pref.defaultCamera) private var cameraRaw = CameraPosition.front.rawValue
    @AppStorage(Pref.defaultTimerMinutes) private var timerMinutes = 50
    @AppStorage(Pref.defaultMode) private var modeRaw = SessionMode.timer.rawValue
    @AppStorage(Pref.recordVideo) private var recordVideo = true

    @State private var videoBytes: Int64 = 0
    @State private var confirmDeleteVideos = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goalMinutes, in: 5...480, step: 5) {
                        LabeledContent("Tagesziel", value: "\(goalMinutes) min")
                    }
                    Picker("Neuer Tag ab", selection: $dayStartHour) {
                        ForEach(0...6, id: \.self) { Text("\($0):00 Uhr").tag($0) }
                    }
                } header: {
                    Text("Streak")
                } footer: {
                    Text("Ein Tag zählt für den Streak, sobald du dein Tagesziel erreichst. Sessions vor \(dayStartHour):00 Uhr zählen noch zum Vortag.")
                }

                Section("Session") {
                    Picker("Standardmodus", selection: $modeRaw) {
                        ForEach(SessionMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper(value: $timerMinutes, in: 5...480, step: 5) {
                        LabeledContent("Timer-Dauer", value: "\(timerMinutes) min")
                    }
                    Toggle("Zeitraffer aufnehmen", isOn: $recordVideo)
                    Picker("Kamera", selection: $cameraRaw) {
                        ForEach(CameraPosition.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }

                Section("Organisation") {
                    NavigationLink {
                        SubjectsView()
                    } label: {
                        Label("Fächer", systemImage: "books.vertical.fill")
                    }
                    NavigationLink {
                        FocusGuideView()
                    } label: {
                        Label("Keine Benachrichtigungen (Fokus)", systemImage: "moon.fill")
                    }
                }

                Section {
                    LabeledContent("Videos", value: ByteCountFormatter.string(fromByteCount: videoBytes, countStyle: .file))
                    Button("Alle Videos löschen", role: .destructive) { confirmDeleteVideos = true }
                        .disabled(videoBytes == 0)
                } header: {
                    Text("Speicher")
                } footer: {
                    Text("Die Lernzeit bleibt erhalten, nur die Videos werden entfernt.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link(destination: URL(string: "https://github.com/elvinsekeric-hue/grind")!) {
                        Label("Quellcode auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear { videoBytes = Storage.videosBytes() }
            .confirmationDialog("Alle Videos löschen?", isPresented: $confirmDeleteVideos, titleVisibility: .visible) {
                Button("Videos löschen", role: .destructive, action: deleteAllVideos)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func deleteAllVideos() {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        sessions.forEach { $0.deleteMedia() }
        try? context.save()
        if let files = try? FileManager.default.contentsOfDirectory(at: Storage.videosDir, includingPropertiesForKeys: nil) {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        videoBytes = Storage.videosBytes()
        Haptics.success()
    }
}

struct SubjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @State private var editing: Subject?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(subjects.filter { !$0.isArchived }) { subject in
                    row(subject)
                }
                .onMove(perform: move)
            } footer: {
                Text("Halten und ziehen zum Sortieren. Nach links wischen zum Archivieren.")
            }

            let archived = subjects.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archiviert") {
                    ForEach(archived) { subject in
                        row(subject)
                    }
                }
            }
        }
        .navigationTitle("Fächer")
        .toolbar {
            Button { creating = true } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { subject in
            SubjectEditor(subject: subject)
        }
        .sheet(isPresented: $creating) {
            SubjectEditor(subject: nil)
        }
    }

    private func row(_ subject: Subject) -> some View {
        Button { editing = subject } label: {
            HStack(spacing: 12) {
                Image(systemName: subject.symbol)
                    .foregroundStyle(subject.color)
                    .frame(width: 32, height: 32)
                    .background(subject.color.opacity(0.15), in: .circle)
                Text(subject.name)
                    .foregroundStyle(subject.isArchived ? .secondary : .primary)
                Spacer()
                Text(DurationFormat.hours(subject.sessions.reduce(0) { $0 + $1.activeSeconds }))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button(subject.isArchived ? "Zurückholen" : "Archivieren") {
                subject.isArchived.toggle()
                try? context.save()
            }
            .tint(subject.isArchived ? .green : .orange)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var active = subjects.filter { !$0.isArchived }
        active.move(fromOffsets: source, toOffset: destination)
        for (index, subject) in active.enumerated() { subject.sortIndex = index }
        try? context.save()
    }
}

struct SubjectEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Subject]
    let subject: Subject?

    @State private var name = ""
    @State private var colorHex = Subject.palette[0]
    @State private var symbol = Subject.symbols[0]
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: symbol)
                            .font(.system(size: 34))
                            .foregroundStyle(Color(hex: colorHex))
                            .frame(width: 76, height: 76)
                            .background(Color(hex: colorHex).opacity(0.18), in: .circle)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    TextField("Name, z. B. Analysis", text: $name)
                }
                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Subject.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if hex == colorHex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Subject.symbols, id: \.self) { s in
                            Image(systemName: s)
                                .frame(width: 40, height: 40)
                                .background(s == symbol ? Color(hex: colorHex).opacity(0.3) : Color.white.opacity(0.06), in: .rect(cornerRadius: 10))
                                .onTapGesture { symbol = s }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if subject != nil {
                    Section {
                        Button("Fach löschen", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Die Sessions bleiben erhalten und werden zu „Ohne Fach“.")
                    }
                }
            }
            .navigationTitle(subject == nil ? "Neues Fach" : "Fach bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Fach löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let subject { context.delete(subject); try? context.save() }
                    SnapshotService.refresh(context)
                    dismiss()
                }
            }
            .onAppear {
                if let subject {
                    name = subject.name
                    colorHex = subject.colorHex
                    symbol = subject.symbol
                } else {
                    colorHex = Subject.palette[all.count % Subject.palette.count]
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let subject {
            subject.name = trimmed
            subject.colorHex = colorHex
            subject.symbol = symbol
        } else {
            context.insert(Subject(name: trimmed, colorHex: colorHex, symbol: symbol, sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
