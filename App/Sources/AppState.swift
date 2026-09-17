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

    public init(supportDirectory: URL? = nil) {
        let support = supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        if renamed {
            cancelFolderNaming(id)
            updateGroupingSummary(for: id)
        }
        loadCurrentPage()
        return renamed
    }
    public func deleteFolder(_ id: UUID) {
        cancelFolderNaming(id)
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
    private var lastGrouping: (id: UUID, folderID: UUID, movedIDs: [UUID], folderWasCreated: Bool)?
    private struct PendingFolderName {
        let groupingID: UUID
        let placeholder: String
        let conversationIDs: Set<UUID>
    }
    private var pendingFolderNames: [UUID: PendingFolderName] = [:]

    public enum FolderNamingOutcome: Equatable, Sendable { case named, needsManualName, discarded }

    /// Drop one conversation onto another: create or merge a folder and move both in.
    /// Passing a name overrides the proposal, which is how inline renaming commits.
    @discardableResult
    public func groupConversations(_ first: UUID, _ second: UUID, name: String? = nil) -> GroupingResult? {
        guard first != second,
              let a = historyEntries.first(where: { $0.id == first }),
              let b = historyEntries.first(where: { $0.id == second }) else { return nil }
        let proposal = TileGrouping.propose(a.tags, b.tags)
        // An explicit or confident name is allowed to merge into an existing
        // folder — that is what dropping onto the same topic twice should do. A
        // placeholder must not, or two unrelated drops end up sharing a folder.
        let folderName: String
        if let name {
            folderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if proposal.isConfident {
            folderName = proposal.suggestedName
        } else {
            folderName = TileGrouping.uniquePlaceholder(existing: notebook.folders.map(\.name))
        }
        // Record whether the folder already existed, so undo only removes what we made.
        let existed = notebook.folders.contains {
            $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        }
        guard let folderID = notebook.createFolder(name: folderName, anchors: proposal.anchors) else { return nil }
        history.move(a.id, to: folderID)
        history.move(b.id, to: folderID)
        let groupingID = UUID()
        lastGrouping = (groupingID, folderID, [a.id, b.id], !existed)
        if name == nil && !proposal.isConfident {
            pendingFolderNames[folderID] = PendingFolderName(
                groupingID: groupingID, placeholder: folderName, conversationIDs: [a.id, b.id])
        }
        lastGroupingSummary = "Grouped 2 into \(folderName)"
        folders = notebook.folders
        refreshHistory()
        return GroupingResult(folderID: folderID,
                              shouldPromptForName: name == nil && !proposal.isConfident)
    }

    /// Injected by DictationController so AppState can reach the local model
    /// without owning it — the same idiom as `retryModels`. Nil until the model
    /// is wired, which keeps AppState constructible in tests and previews.
    public var nameFolderWithModel: ((String, String) async -> String?)?

    /// Ask the local model to name a folder a drop just created, then apply it.
    /// Only a still-current request may rename or prompt for manual naming.
    /// Discarded requests must not steal focus from newer user actions.
    @discardableResult
    public func nameGroupedFolder(_ folderID: UUID, _ first: UUID, _ second: UUID) async -> FolderNamingOutcome {
        guard let request = pendingFolderNames[folderID],
              request.conversationIDs == Set([first, second]),
              isNamingCurrent(request, folderID: folderID),
              let a = historyEntries.first(where: { $0.id == first }),
              let b = historyEntries.first(where: { $0.id == second }) else { return .discarded }
        defer {
            if pendingFolderNames[folderID]?.groupingID == request.groupingID {
                pendingFolderNames[folderID] = nil
            }
        }
        let suggested = await nameFolderWithModel?(
            a.polished.isEmpty ? a.raw : a.polished,
            b.polished.isEmpty ? b.raw : b.polished)
        guard !Task.isCancelled, isNamingCurrent(request, folderID: folderID) else { return .discarded }
        guard let name = suggested?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return lastGrouping?.id == request.groupingID ? .needsManualName : .discarded
        }
        return applyGeneratedFolderName(name, to: folderID) ? .named : .discarded
    }

    /// Called when editing starts, so even an uncommitted draft beats the model.
    public func cancelFolderNaming(_ folderID: UUID) {
        pendingFolderNames[folderID] = nil
    }

    private func isNamingCurrent(_ request: PendingFolderName, folderID: UUID) -> Bool {
        pendingFolderNames[folderID]?.groupingID == request.groupingID
            && notebook.folders.first(where: { $0.id == folderID })?.name == request.placeholder
            && request.conversationIDs.allSatisfy { id in
                history.entries.contains { $0.id == id && $0.folderID == folderID }
            }
    }

    private func updateGroupingSummary(for folderID: UUID) {
        guard let grouping = lastGrouping, grouping.folderID == folderID,
              let folder = notebook.folders.first(where: { $0.id == folderID }) else { return }
        lastGroupingSummary = "Grouped \(grouping.movedIDs.count) into \(folder.name)"
    }

    /// Apply a generated name, merging when it is already taken. `renameFolder`
    /// refuses a duplicate, and leaving the placeholder would waste the answer —
    /// so the conversations move into the folder that owns the name, exactly as
    /// `createFolder` would have merged them had the name been known at drop time.
    private func applyGeneratedFolderName(_ name: String, to folderID: UUID) -> Bool {
        guard notebook.folders.contains(where: { $0.id == folderID }) else { return false }
        if notebook.renameFolder(folderID, name: name) {
            folders = notebook.folders
            updateGroupingSummary(for: folderID)
            return true
        }
        guard let target = notebook.folders.first(where: {
            $0.id != folderID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { return false }
        for entry in history.entries where entry.folderID == folderID {
            notebook.reinforceAnchors(target.id, with: entry.tags)
            history.move(entry.id, to: target.id)
        }
        notebook.mergeFolder(folderID, into: target.id)
        // Undo now has to reverse a merge: the surviving folder predates this
        // grouping, so undo must never delete it.
        if var grouping = lastGrouping, grouping.folderID == folderID {
            grouping.folderID = target.id
            grouping.folderWasCreated = false
            lastGrouping = grouping
            updateGroupingSummary(for: target.id)
        }
        loadCurrentPage()
        refreshHistory()
        return true
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
        cancelFolderNaming(grouping.folderID)
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
