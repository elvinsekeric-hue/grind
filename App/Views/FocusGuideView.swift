import SwiftUI

struct FocusGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let symbol: String
    }

    private let steps: [Step] = [
        Step(id: 1, title: "Fokus „Lernen“ anlegen",
             detail: "Einstellungen › Fokus › + › Eigener › Name „Lernen“. Bei Personen und Apps niemanden erlauben, nur Grind hinzufügen. So kommt nur die Warnung durch, wenn du die App verlässt.",
             symbol: "moon.fill"),
        Step(id: 2, title: "Automation beim Öffnen",
             detail: "Kurzbefehle › Automation › + › App › Grind auswählen, „Wird geöffnet“ anhaken, „Sofort ausführen“. Aktion „Fokus festlegen“ › Lernen › Ein.",
             symbol: "arrow.up.forward.app.fill"),
        Step(id: 3, title: "Automation beim Schließen",
             detail: "Nochmal + › App › Grind, diesmal „Wird geschlossen“, „Sofort ausführen“. Aktion „Fokus festlegen“ › Lernen › Aus.",
             symbol: "arrow.down.forward.app.fill"),
        Step(id: 4, title: "Während der Session",
             detail: "Nicht die Sperrtaste drücken. Grind macht den Bildschirm selbst schwarz und hält die Kamera an. Gesperrt zählt wie App verlassen.",
             symbol: "lock.slash.fill")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.emberGradient)
                    Text("Keine Ablenkung")
                        .font(.largeTitle.bold())
                    Text("iOS lässt Apps den Fokus-Modus nicht selbst einschalten. Mit zwei Kurzbefehl-Automationen geht es trotzdem vollautomatisch: Grind öffnen schaltet Benachrichtigungen ab, Grind schließen wieder an. Einmal 2 Minuten einrichten.")
                        .foregroundStyle(.secondary)
                }

                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(Color.ember.opacity(0.18))
                            Text("\(step.id)")
                                .font(.headline)
                                .foregroundStyle(Color.ember)
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(step.title, systemImage: step.symbol)
                                .font(.headline)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label("Kurzbefehle öffnen", systemImage: "square.2.layers.3d.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.ember)

                Text("Tipp: Im Fokus „Lernen“ kannst du unter „Sperrbildschirm“ auch einen dunklen Bildschirm wählen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OnboardingView: View {
    let finish: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                pageView(symbol: "flame.fill",
                         title: "Willkommen bei Grind",
                         text: "Lerne jeden Tag mindestens dein Tagesziel und halte deinen Streak am Leben.")
                    .tag(0)
                pageView(symbol: "camera.aperture",
                         title: "Zeitraffer statt Ausreden",
                         text: "Grind filmt dich beim Lernen und macht aus Stunden ein Video von etwa 45 Sekunden. Der Bildschirm wird dabei komplett schwarz.")
                    .tag(1)
                pageView(symbol: "hand.raised.fill",
                         title: "Handy bleibt liegen",
                         text: "Verlässt du die App, pausiert die Zeit. Nach 2 Minuten außerhalb endet die Session. Sperr das Handy nicht, Grind kümmert sich ums Display.")
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    Task {
                        _ = await TimelapseRecorder.requestAccess()
                        SessionController.requestNotificationPermission()
                        finish()
                    }
                }
            } label: {
                Text(page < 2 ? "Weiter" : "Kamera & Mitteilungen erlauben")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.ember)
            .padding(20)
        }
        .background(
            RadialGradient(colors: [Color.ember.opacity(0.25), .black], center: .top, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()
        )
    }

    private func pageView(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 80))
                .foregroundStyle(.emberGradient)
                .shadow(color: .ember.opacity(0.5), radius: 30)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}
