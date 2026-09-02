import SwiftUI

enum TallyAccentColor: String, CaseIterable, Identifiable {
    case blue
    case purple
    case pink
    case green
    case orange
    case red
    case teal
    case indigo

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue:
            return Color(hex: "0A84FF") ?? .blue
        case .purple:
            return Color(hex: "9000FF") ?? .purple
        case .pink:
            return Color(hex: "FF7EFF") ?? .pink
        case .green:
            return Color(hex: "30D158") ?? .green
        case .orange:
            return Color(hex: "FF9F0A") ?? .orange
        case .red:
            return Color(hex: "FF453A") ?? .red
        case .teal:
            return Color(hex: "64D2FF") ?? .teal
        case .indigo:
            return Color(hex: "6C72F2") ?? .indigo
        }
    }
}
