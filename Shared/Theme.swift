import SwiftUI

extension Color {
    static let ember = Color(red: 1.0, green: 0.42, blue: 0.10)
    static let emberDeep = Color(red: 0.90, green: 0.20, blue: 0.08)
    static let emberGlow = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let surface = Color(white: 0.09)
    static let surfaceRaised = Color(white: 0.13)

    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension ShapeStyle where Self == LinearGradient {
    static var emberGradient: LinearGradient {
        LinearGradient(colors: [.emberGlow, .ember, .emberDeep], startPoint: .top, endPoint: .bottom)
    }
}

/// Five intensity levels for heatmaps, based on the daily goal.
enum HeatLevel {
    static func level(seconds: Double, goal: Double) -> Int {
        guard seconds > 0 else { return 0 }
        let g = max(goal, 60)
        if seconds < g * 0.5 { return 1 }
        if seconds < g { return 2 }
        if seconds < g * 2 { return 3 }
        return 4
    }

    static func color(_ level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.07)
        case 1: return Color.ember.opacity(0.28)
        case 2: return Color.ember.opacity(0.50)
        case 3: return Color.ember.opacity(0.78)
        default: return Color.emberGlow
        }
    }
}
