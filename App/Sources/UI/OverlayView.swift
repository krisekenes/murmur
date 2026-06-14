import SwiftUI

public struct OverlayView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AppState) { self.state = state }

    public var body: some View {
        HStack(spacing: 12) {
            WaveformBars(level: level, animated: !reduceMotion)
                .frame(width: 80, height: 24)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: Theme.pillSize.width, height: Theme.pillSize.height)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    private var level: Float {
        // inputLevel is raw RMS (~0.01–0.1 for speech); amplify so the bars visibly track the voice.
        if case .listening = state.phase { return max(0.06, min(1, state.inputLevel * 10)) } else { return 0.1 }
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

struct WaveformBars: View {
    let level: Float
    let animated: Bool
    @State private var history: [CGFloat] = Array(repeating: 0.12, count: 16)

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(history.indices, id: \.self) { i in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(height: max(3, history[i] * geo.size.height))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .onChange(of: level) { _, newValue in
            // Scroll the real input level across the bars for a voice-reactive bounce.
            var next = history
            next.removeFirst()
            next.append(min(1, max(0.06, CGFloat(newValue) * 1.3)))
            if animated {
                withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { history = next }
            } else {
                history = next
            }
        }
    }
}
