import SwiftUI

/// Static stars: no timers, random values during rendering, or motion behind text.
struct NightSky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.canvas, Theme.midnight], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.15, green: 0.23, blue: 0.34).opacity(0.24), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 650)
            Canvas { context, size in
                for index in 0..<90 {
                    let x = fraction(Double(index + 1) * 12.9898) * size.width
                    let y = fraction(Double(index + 1) * 78.233) * size.height
                    let bright = index % 13 == 0
                    let radius: CGFloat = bright ? 1.15 : 0.65
                    let point = CGPoint(x: x, y: y)
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(Theme.ink.opacity(bright ? 0.36 : 0.16)))
                    if bright {
                        var cross = Path()
                        cross.move(to: CGPoint(x: point.x - 3, y: point.y))
                        cross.addLine(to: CGPoint(x: point.x + 3, y: point.y))
                        cross.move(to: CGPoint(x: point.x, y: point.y - 3))
                        cross.addLine(to: CGPoint(x: point.x, y: point.y + 3))
                        context.stroke(cross, with: .color(Theme.ink.opacity(0.10)), lineWidth: 0.6)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fraction(_ value: Double) -> Double {
        let value = sin(value) * 43758.5453
        return value - floor(value)
    }
}

enum ConstellationStyle {
    static func seed(for id: UUID) -> UInt64 {
        id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    static func tint(for id: UUID) -> Color {
        let colors: [Color] = [Theme.accent, Color(red: 0.55, green: 0.72, blue: 0.85),
                               Color(red: 0.63, green: 0.76, blue: 0.66), Color(red: 0.73, green: 0.66, blue: 0.84),
                               Color(red: 0.83, green: 0.65, blue: 0.58)]
        return colors[Int(seed(for: id) % UInt64(colors.count))]
    }
}

/// The UUID, rather than the editable name or contents, gives a folder its identity.
struct Constellation: View {
    let seed: UInt64
    var tint: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            let points = (0..<5).map { index in
                CGPoint(x: size.width * (0.09 + Double(index) * 0.205),
                        y: size.height * (0.22 + Double((seed >> (index * 8)) & 255) / 255 * 0.56))
            }
            var lines = Path()
            lines.addLines(points)
            context.stroke(lines, with: .color(tint.opacity(0.28)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            for (index, point) in points.enumerated() {
                let radius: CGFloat = index == 2 ? 2.6 : 1.7
                let star = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                var glow = context
                glow.addFilter(.shadow(color: tint.opacity(0.7), radius: 5))
                glow.fill(star, with: .color(tint.opacity(index == 2 ? 1 : 0.75)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A steady point at rest, opening into a waveform driven by actual microphone input.
struct VoiceSignal: View {
    let phase: AppState.Phase
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var listening: Bool { if case .listening = phase { return true }; return false }
    private var active: Bool {
        switch phase { case .listening, .transcribing, .polishing: return true; default: return false }
    }

    var body: some View {
        HStack(spacing: active ? 3 : 0) {
            Circle().fill(Theme.accent)
                .frame(width: active ? 5 : 7, height: active ? 5 : 7)
                .shadow(color: Theme.accent.opacity(active ? 0.7 : 0.35), radius: active ? 8 : 4)
            ForEach(0..<11, id: \.self) { index in
                Capsule().fill(Theme.accent.opacity(0.9))
                    .frame(width: active ? 3 : 0, height: height(index))
                    .opacity(active ? 1 : 0)
            }
        }
        .frame(width: 76, height: 32)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: active)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func height(_ index: Int) -> CGFloat {
        guard active else { return 3 }
        let envelope = 0.35 + 0.65 * abs(sin(Double(index + 1) * 1.6))
        let amplitude = reduceMotion || !listening ? 0.4 : min(1, max(0.08, Double(level) * 12))
        return 4 + 23 * envelope * amplitude
    }
}
