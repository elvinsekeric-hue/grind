import Foundation

public enum DurationFormat {
    /// "45 s", "25 min", "1 h 05 min"
    public static func short(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : String(format: "%d h %02d min", h, m)
    }

    /// "25:03" or "1:05:03"
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "12,5 h" (German decimal comma), "40 min" under one hour
    public static func hours(_ seconds: Double) -> String {
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) min" }
        let value = (seconds / 3600 * 10).rounded() / 10
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return "\(text) h"
    }

    /// Minutes as integer, rounded down.
    public static func minutes(_ seconds: Double) -> Int { Int(max(0, seconds) / 60) }
}
