import SwiftUI

@main
struct MurmurApp: App {
    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: "waveform") {
            Text("Murmur \(MurmurCoreVersionShim.version)")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

// Proves the MurmurCore link works; removed once real menu lands in Task 12.
import MurmurCore
enum MurmurCoreVersionShim { static let version = MurmurCore.version }
