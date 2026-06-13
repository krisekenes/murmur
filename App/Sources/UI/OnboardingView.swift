import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var state: AppState
    var onComplete: () -> Void
    @State private var micOK = Permissions.microphoneGranted
    @State private var axOK = Permissions.accessibilityGranted

    public init(state: AppState, onComplete: @escaping () -> Void) {
        self.state = state; self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Murmur").font(.title.bold())
            row("Microphone", "Murmur transcribes your speech on-device.", micOK) {
                Task { micOK = await Permissions.requestMicrophone() }
            }
            row("Accessibility & Input Monitoring", "Needed to detect your hotkey and paste text.", axOK) {
                Permissions.promptAccessibility(); axOK = Permissions.accessibilityGranted
            }
            Text("Tip: set System Settings → Keyboard → \"Press 🌐 to\" → \"Do Nothing\" so Fn is free for Murmur.")
                .font(.caption).foregroundStyle(.secondary)
            if case .downloading(let p) = state.phase {
                ProgressView("Downloading models…", value: p)
            }
            Spacer()
            Button("Finish") { onComplete() }.disabled(!(micOK && axOK)).keyboardShortcut(.defaultAction)
        }
        .padding(24).frame(width: 460, height: 360)
    }

    @ViewBuilder private func row(_ title: String, _ why: String, _ ok: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.accent : .secondary)
            VStack(alignment: .leading) { Text(title).bold(); Text(why).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !ok { Button("Grant", action: action) }
        }
    }
}
