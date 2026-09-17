import AppKit
import SwiftUI
import MurmurCore

/// Render synthetic examples through the real views, without starting dictation
/// services or reading the user's notebook. Output is ignored under .build/.
@main
struct NightSkyPreview {
    @MainActor static func main() throws {
        UserDefaults.standard.setVolatileDomain(["betaMode": true], forName: UserDefaults.argumentDomain)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-preview-\(UUID())")
        let state = AppState(supportDirectory: temporary)
        let folderNames = ["Interviews", "Product ideas", "Weekends"]
        for name in folderNames { state.createFolder(name) }
        let filed: [(String, String, String)] = [
            ("Interviews", "interview", "Follow up with a concrete example of how we measured the outcome."),
            ("Interviews", "interview", "Tell the story about helping the team find clarity when the roadmap changed."),
            ("Interviews", "interview", "Questions to ask: how does the team decide what is worth building next?"),
            ("Product ideas", "ideas", "A thought should be easy to capture, even before I know what to call it."),
            ("Product ideas", "ideas", "Make the small moments feel considered. The details are the experience."),
            ("Weekends", "personal", "A long walk, a little coffee shop, and a book I have been meaning to finish.")
        ]
        for (folder, tag, text) in filed {
            let id = UUID()
            state.appendDictation(HistoryEntry(id: id, raw: text, polished: text, createdAt: Date(), appName: "Murmur", tags: [tag]))
            state.moveConversation(id, to: state.folders.first { $0.name == folder }!.id)
        }
        let thoughts = [
            ("ideas", "What if the interface gave every thought a little room to breathe? Something warm, quiet, and easy to come back to."),
            ("work", "The next demo should start with the problem we are solving. Show the moment it makes someone's day easier."),
            ("learning", "Good questions are usually more useful than quick answers. Leave room to discover something unexpected."),
            ("personal", "Remember to make time for the small projects. The ones I keep thinking about on the walk home.")
        ]
        for (tag, text) in thoughts.reversed() {
            state.appendDictation(HistoryEntry(id: UUID(), raw: text, polished: text, createdAt: Date(), appName: "Murmur", tags: [tag]))
        }
        try render(MainWindowView(state: state), name: "night-sky-library", size: CGSize(width: 1120, height: 820))
        try render(MainWindowView(state: state), name: "night-sky-compact", size: CGSize(width: 740, height: 620))
        let empty = AppState(supportDirectory: temporary.appendingPathComponent("empty"))
        try render(MainWindowView(state: empty), name: "night-sky-empty", size: CGSize(width: 1000, height: 680))
        state.phase = .listening(locked: false)
        state.inputLevel = 0.06
        try render(OverlayView(state: state), name: "night-sky-recording", size: Theme.pillSize)
        print("Rendered previews under .build/preview/")
    }

    @MainActor static func render<Content: View>(_ content: Content, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark).transaction { $0.disablesAnimations = true })
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFront(nil)
        host.frame = CGRect(origin: .zero, size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }
}
