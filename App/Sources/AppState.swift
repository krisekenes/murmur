import SwiftUI
import MurmurCore

@MainActor
public final class AppState: ObservableObject {
    public enum Phase: Equatable { case idle, listening(locked: Bool), transcribing, polishing, downloading(Double), error(String) }

    @Published public var organizedConversationCount = 0
    private var lastOrganization: [UUID: UUID] = [:]

    @Published public var notice: String?
    @Published public var canRetryModels = false
    public var retryModels: (() -> Void)?
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
    @Published public var folders: [NoteFolder] = []
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
        folders = notebook.folders
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

    public func newPage(folderID: UUID? = nil) { notebook.newPage(folderID: folderID); loadCurrentPage() }
    public func selectPage(_ id: UUID) { notebook.select(id); loadCurrentPage() }
    public func deleteCurrentPage() { notebook.delete(currentPageID); loadCurrentPage() }

    public func createFolder(_ name: String) { notebook.createFolder(name: name); loadCurrentPage() }
    public func renameFolder(_ id: UUID, name: String) -> Bool {
        let renamed = notebook.renameFolder(id, name: name)
        loadCurrentPage()
        return renamed
    }
    public func deleteFolder(_ id: UUID) {
        history.unfile(folderID: id)
        refreshHistory()
        notebook.deleteFolder(id)
        loadCurrentPage()
    }
    public func addConversationTag(_ tag: String, id: UUID) { history.addTag(tag, to: id); refreshHistory() }
    public func removeConversationTag(_ tag: String, id: UUID) { history.removeTag(tag, from: id); refreshHistory() }
    public func moveConversation(_ id: UUID, to folderID: UUID?) {
        guard folderID == nil || folders.contains(where: { $0.id == folderID }) else { return }
        history.move(id, to: folderID)
        refreshHistory()
    }
    public func organizeConversations(_ suggestions: [FolderSuggestion]) {
        let moves = SmartFolderOrganizer.apply(suggestions, history: history, notebook: notebook)
        if !moves.isEmpty {
            lastOrganization = moves
            organizedConversationCount = moves.count
        }
        folders = notebook.folders
        refreshHistory()
    }

    public func undoConversationOrganization() {
        history.undoOrganization(lastOrganization)
        lastOrganization = [:]
        organizedConversationCount = 0
        refreshHistory()
    }

    private func refreshHistory() {
        historyEntries = history.entries
        recentPeek = Array(history.entries.prefix(3))
    }
    public func movePage(to id: UUID?) { notebook.moveCurrent(to: id); loadCurrentPage() }
    public func addTag(_ tag: String) { notebook.addTag(tag); pages = notebook.pages }
    public func removeTag(_ tag: String) { notebook.removeTag(tag); pages = notebook.pages }

    private func loadCurrentPage() {
        pages = notebook.pages
        folders = notebook.folders
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
