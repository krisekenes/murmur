import SwiftUI
import MurmurCore

@main
struct MurmurApp: App {
    @StateObject private var state = AppState()

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: menuIcon(for: state.phase))
        }

        Window("History", id: "history") { HistoryView(state: state) }
            .windowResizability(.contentSize)
        Settings { SettingsView(state: state) }
    }

    private func menuIcon(for phase: AppState.Phase) -> String {
        switch phase {
        case .idle: return "waveform"
        case .listening: return "waveform.circle.fill"
        case .transcribing, .polishing: return "waveform.badge.magnifyingglass"
        case .downloading: return "arrow.down.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    var body: some View {
        Toggle("Polish with AI", isOn: $state.polishEnabled)
        Divider()
        if state.recentPeek.isEmpty {
            Text("No dictations yet").foregroundStyle(.secondary)
        } else {
            ForEach(state.recentPeek) { entry in
                Button(String(entry.polished.prefix(40)) + (entry.polished.count > 40 ? "…" : "")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.polished, forType: .string)
                }
            }
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Murmur") { NSApplication.shared.terminate(nil) }
    }
}
