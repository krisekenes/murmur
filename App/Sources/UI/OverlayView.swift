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
        if case .listening = state.phase { return 0.6 } else { return 0.1 }
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
    @State private var phase = 0.0
    var body: some View {
        Canvas { ctx, size in
            let bars = 16
            let w = size.width / CGFloat(bars * 2)
            for i in 0..<bars {
                let n = animated ? (sin(phase + Double(i) * 0.6) * 0.5 + 0.5) : 0.5
                let h = max(2, CGFloat(n) * CGFloat(level) * size.height)
                let x = CGFloat(i) * w * 2 + w
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2), with: .color(Theme.accent))
            }
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}
