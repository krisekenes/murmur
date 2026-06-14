import SwiftUI
import MurmurCore

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: appDelegate.state)
        } label: {
            Image(systemName: menuIcon(for: appDelegate.state.phase))
                .symbolRenderingMode(.palette)
                .foregroundStyle(isActive(appDelegate.state.phase) ? Theme.accent : Color.primary)
        }

        Window("Murmur", id: "main") { MainWindowView(state: appDelegate.state) }
            .windowResizability(.contentMinSize)
            .defaultSize(width: 860, height: 560)
        Settings { SettingsView(state: appDelegate.state) }
    }

    private func isActive(_ phase: AppState.Phase) -> Bool {
        switch phase { case .idle, .error: return false; default: return true }
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var controller: DictationController?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let controller = DictationController(state: state)
        controller.startServices()
        self.controller = controller

        if !Permissions.accessibilityGranted || !Permissions.microphoneGranted {
            presentOnboarding()
        }
    }

    private func presentOnboarding() {
        let root = OnboardingView(state: state) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            // Accessibility may have just been granted; the original event tap
            // could not be created without it, so rebuild the hotkey monitor.
            self?.controller?.restartHotkey()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to Murmur"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Murmur") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
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
