import SwiftUI

public struct OverlayView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) { self.state = state }

    public var body: some View {
        HStack(spacing: 12) {
            VoiceSignal(phase: state.phase, level: state.inputLevel)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: Theme.pillSize.width, height: Theme.pillSize.height)
        .background(Capsule().fill(Theme.midnight.opacity(0.96)))
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    private var label: String {
        switch state.phase {
        case .listening(let locked): return locked ? "Listening (locked)" : "Listening"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing…"
        default: return ""
        }
    }
}
