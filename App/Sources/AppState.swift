import SwiftUI
import MurmurCore

@MainActor
public final class AppState: ObservableObject {
    public enum Phase: Equatable { case idle, listening(locked: Bool), transcribing, polishing, downloading(Double), error(String) }

    @Published public var phase: Phase = .idle
    @Published public var polishEnabled: Bool = UserDefaults.standard.object(forKey: "polishEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: "polishEnabled") }
    }
    @Published public var hotkey: HotkeyChoice = HotkeyChoice(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "fn") ?? .fn {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: "hotkey") }
    }
    @Published public var recentPeek: [HistoryEntry] = []
    @Published public var historyEntries: [HistoryEntry] = []
    @Published public var inputLevel: Float = 0
    @Published public var scratchpad: String = "" {
        didSet {
            guard !isLoadingPage else { return }
            notebook.updateCurrent(content: scratchpad)
            pages = notebook.pages
        }
    }
    @Published public var pages: [ScratchpadPage] = []
    @Published public var currentPageID: UUID = UUID()

    public let history: HistoryStore
    public let vocabulary: VocabularyStore
    public let notebook: NotebookStore
    private var isLoadingPage = false

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
        history = (try? HistoryStore(fileURL: support.appendingPathComponent("history.json"), limit: 200))
            ?? (try! HistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("history.json")))
        vocabulary = (try? VocabularyStore(fileURL: support.appendingPathComponent("vocabulary.json")))
            ?? (try! VocabularyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary.json")))
        notebook = NotebookStore(
            fileURL: support.appendingPathComponent("notebook.json"),
            legacyTextURL: support.appendingPathComponent("scratchpad.txt"))
        recentPeek = Array(history.entries.prefix(3))
        historyEntries = history.entries
        pages = notebook.pages
        currentPageID = notebook.currentID
        isLoadingPage = true
        scratchpad = notebook.currentContent
        isLoadingPage = false
    }

    /// Append a feed entry's text into the current scratchpad page on its own line.
    public func appendToScratchpad(_ text: String) {
        if scratchpad.isEmpty {
            scratchpad = text
        } else {
            scratchpad += (scratchpad.hasSuffix("\n") ? "" : "\n") + text
        }
    }

    public func newPage() { notebook.newPage(); loadCurrentPage() }
    public func selectPage(_ id: UUID) { notebook.select(id); loadCurrentPage() }
    public func deleteCurrentPage() { notebook.delete(currentPageID); loadCurrentPage() }

    private func loadCurrentPage() {
        pages = notebook.pages
        currentPageID = notebook.currentID
        isLoadingPage = true
        scratchpad = notebook.currentContent
        isLoadingPage = false
    }

    public func appendDictation(_ entry: HistoryEntry) {
        history.append(entry)
        historyEntries = history.entries
        recentPeek = Array(history.entries.prefix(3))
    }

    public func deleteDictation(id: UUID) {
        history.delete(id: id)
        historyEntries = history.entries
        recentPeek = Array(history.entries.prefix(3))
    }
}
