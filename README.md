# Grind

Lern-App mit Zeitraffer und Streak. Handy hinstellen, Session starten, Bildschirm wird schwarz, Grind filmt dich im Zeitraffer. Ab 25 Minuten am Tag wächst der Streak.

## Funktionen

- **Sessions** als Timer (25/50/90 min oder eigene Dauer) oder offene Stoppuhr, mit Pause
- **Zeitraffer** mit Front- oder Rückkamera. Egal wie lang die Session ist, das Video dauert am Ende etwa 45 Sekunden (Frames werden laufend ausgedünnt, max. ~2400 Bilder auf der Platte)
- **Schwarzer Bildschirm** während der Aufnahme: Helligkeit 0, kein Auto-Lock, kurz antippen zeigt Zeit und Steuerung, Beenden per Gedrückthalten
- **Disziplin**: App verlassen pausiert die Zeit, nach 2 Minuten außerhalb endet die Session. Mitteilung beim Verlassen und 30 s vor Schluss
- **Streak** mit Tagesziel (Standard 25 min), Tagesbeginn einstellbar (Standard 4:00, Nachtsessions zählen zum Vortag), Rekord
- **Fächer** mit Farbe und Symbol, Statistik je Fach
- **Statistik**: Balken pro Tag/Monat nach Fach, Aktivitäts-Heatmap, Tageszeit-Verteilung, Kennzahlen
- **Videos**: Galerie, Player, in Fotos sichern, teilen
- **Widgets** für Home- und Sperrbildschirm (Streak, heutige Minuten, Woche)
- **Absturzsicher**: Läuft eine Session beim App-Kill, wird sie beim nächsten Start samt Video gesichert
- **Fokus-Anleitung**: Kurzbefehl-Automationen, die beim Öffnen von Grind Benachrichtigungen abschalten

## Installation

1. Auf dem iPhone in Safari den neuesten Build öffnen: [Releases › latest](https://github.com/elvinsekeric-hue/grind/releases/tag/latest) › `Grind.ipa`
2. Mit SideStore öffnen und installieren
3. Widget: Homescreen lange drücken › + › Grind

## Aufbau

- `Packages/GrindCore`: reine Logik (Tage, Streak, Frame-Ausdünnung, Formatierung) mit Tests
- `App/`: SwiftUI-App (SwiftData, AVFoundation, Charts)
- `Widget/`: WidgetKit-Erweiterung, liest einen JSON-Snapshot aus der App Group
- Build: GitHub Actions erzeugt das Xcode-Projekt mit XcodeGen und baut eine unsignierte IPA
