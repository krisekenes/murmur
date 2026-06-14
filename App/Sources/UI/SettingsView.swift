import SwiftUI
import ServiceManagement
import MurmurCore

public struct SettingsView: View {
    @ObservedObject var state: AppState
    public init(state: AppState) { self.state = state }

    public var body: some View {
        TabView {
            GeneralTab(state: state).tabItem { Label("General", systemImage: "gearshape") }
            VocabularyTab(state: state).tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 320)
    }
}

struct GeneralTab: View {
    @ObservedObject var state: AppState
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    var body: some View {
        Form {
            Picker("Hotkey", selection: $state.hotkey) {
                Text("Fn (Globe)").tag(HotkeyChoice.fn)
                Text("Right Option").tag(HotkeyChoice.rightOption)
            }
            Toggle("Polish with AI", isOn: $state.polishEnabled)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
                }
        }.padding()
    }
}

struct VocabularyTab: View {
    @ObservedObject var state: AppState
    @State private var newWord = ""
    @State private var words: [String] = []
    var body: some View {
        VStack {
            HStack {
                TextField("Add a name or term", text: $newWord)
                Button("Add") { state.vocabulary.add(newWord); newWord = ""; words = state.vocabulary.words }
            }
            List {
                ForEach(words, id: \.self) { w in
                    HStack { Text(w); Spacer(); Button("Remove") { state.vocabulary.remove(w); words = state.vocabulary.words } }
                }
            }
        }
        .padding()
        .onAppear { words = state.vocabulary.words }
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Murmur").font(.title2.bold())
            Text("Fully local dictation. Audio never leaves your Mac.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Speech: NVIDIA Parakeet (CC-BY-4.0) via FluidAudio").font(.caption2)
            Text("Polish: Qwen3.5-2B via MLX").font(.caption2)
        }.padding()
    }
}
