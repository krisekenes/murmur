import SwiftUI

/// Small status indicator mirroring the dictation phase, shared visual vocabulary
/// with the menu-bar icon and overlay pill.
struct StatusDot: View {
    let phase: AppState.Phase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(active ? 0.7 : 0), radius: 4)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var active: Bool {
        if case .idle = phase { return false }
        if case .error = phase { return false }
        return true
    }

    private var color: Color {
        switch phase {
        case .idle: return .secondary.opacity(0.5)
        case .error: return .red
        default: return Theme.accent
        }
    }

    private var label: String {
        switch phase {
        case .idle: return "Ready"
        case .listening(let locked): return locked ? "Listening (locked)" : "Listening"
        case .transcribing: return "Transcribing"
        case .polishing: return "Polishing"
        case .downloading: return "Preparing models"
        case .error: return "Error"
        }
    }
}
