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

    // MARK: - Beta springboard

    @Published public var betaMode: Bool = UserDefaults.standard.bool(forKey: "betaMode") {
        didSet { UserDefaults.standard.set(betaMode, forKey: "betaMode") }
    }

    public struct GroupingResult: Equatable, Sendable {
        public let folderID: UUID
        /// True when the name was a fallback and the UI should focus the name field.
        public let shouldPromptForName: Bool
    }

    /// Non-nil while the last grouping can still be undone this session.
    @Published public var lastGroupingSummary: String?
    private var lastGrouping: (folderID: UUID, movedIDs: [UUID], folderWasCreated: Bool)?

    /// Drop one conversation onto another: create or merge a folder and move both in.
    /// Passing a name overrides the proposal, which is how inline renaming commits.
    @discardableResult
    public func groupConversations(_ first: UUID, _ second: UUID, name: String? = nil) -> GroupingResult? {
        guard first != second,
              let a = historyEntries.first(where: { $0.id == first }),
              let b = historyEntries.first(where: { $0.id == second }) else { return nil }
        let proposal = TileGrouping.propose(a.tags, b.tags)
        let folderName = (name ?? proposal.suggestedName).trimmingCharacters(in: .whitespacesAndNewlines)
        // Record whether the folder already existed, so undo only removes what we made.
        let existed = notebook.folders.contains {
            $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        }
        guard let folderID = notebook.createFolder(name: folderName, anchors: proposal.anchors) else { return nil }
        history.move(a.id, to: folderID)
        history.move(b.id, to: folderID)
        lastGrouping = (folderID, [a.id, b.id], !existed)
        lastGroupingSummary = "Grouped 2 into \(folderName)"
        folders = notebook.folders
        refreshHistory()
        return GroupingResult(folderID: folderID,
                              shouldPromptForName: name == nil && !proposal.isConfident)
    }

    /// Drop a conversation onto an existing folder: file it and strengthen the anchors.
    public func fileConversation(_ id: UUID, into folderID: UUID) {
        guard let entry = historyEntries.first(where: { $0.id == id }),
              entry.folderID != folderID,
              folders.contains(where: { $0.id == folderID }) else { return }
        notebook.reinforceAnchors(folderID, with: entry.tags)
        history.move(id, to: folderID)
        folders = notebook.folders
        refreshHistory()
    }

    /// Rename a tile: promote a tag to the front, where the springboard reads it.
    public func setPrimaryConversationTag(_ tag: String, id: UUID) {
        history.setPrimaryTag(tag, for: id)
        refreshHistory()
    }

    /// Reverse the last grouping. Unfiles only entries still in that folder, so a
    /// manual move made afterwards survives. Removes the folder only if this action
    /// created it and nothing — conversation or scratchpad note — remains inside.
    public func undoLastGrouping() {
        guard let grouping = lastGrouping else { return }
        for id in grouping.movedIDs
        where history.entries.first(where: { $0.id == id })?.folderID == grouping.folderID {
            history.move(id, to: nil)
        }
        if grouping.folderWasCreated,
           !history.entries.contains(where: { $0.folderID == grouping.folderID }),
           !notebook.pages.contains(where: { $0.folderID == grouping.folderID }) {
            notebook.deleteFolder(grouping.folderID)
        }
        lastGrouping = nil
        lastGroupingSummary = nil
        folders = notebook.folders
        refreshHistory()
    }

    /// NoteFolder is shared with the scratchpad, so a folder tile must count both
    /// kinds of content or it misreports what deleting the folder would touch.
    public func conversationCount(inFolder id: UUID) -> Int {
        historyEntries.reduce(0) { $0 + ($1.folderID == id ? 1 : 0) }
    }

    public func noteCount(inFolder id: UUID) -> Int {
        pages.reduce(0) { $0 + ($1.folderID == id ? 1 : 0) }
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
