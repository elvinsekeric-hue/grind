import Foundation
import GrindCore

/// Shared container between app and widget.
/// SideStore rewrites App Group IDs (it appends the team ID) and writes the real
/// IDs into the `ALTAppGroups` Info.plist key, so we read that first.
enum AppGroup {
    static let defaultID = "group.de.elvin.grind"

    static var identifier: String {
        if let id = pick(Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups")) { return id }
        // Inside the widget extension: look at the host app's Info.plist.
        let hostInfo = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        if let dict = NSDictionary(contentsOf: hostInfo), let id = pick(dict["ALTAppGroups"]) { return id }
        return defaultID
    }

    private static func pick(_ value: Any?) -> String? {
        guard let groups = value as? [String], !groups.isEmpty else { return nil }
        return groups.first { $0.contains("grind") } ?? groups.first
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL, let data = try? snapshot.encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
