import SwiftUI
import SayoneCore

extension DrinkTint {
    var color: Color {
        switch self {
        case .blue: return Color.blue
        case .teal: return Color.teal
        case .brown: return Color.brown
        case .red: return Color.red
        case .orange: return Color.orange
        case .green: return Color.green
        case .purple: return Color.purple
        case .gray: return Color.gray
        }
    }

    var background: Color {
        color.opacity(0.18)
    }
}
