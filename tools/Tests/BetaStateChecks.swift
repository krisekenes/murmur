import Foundation
import MurmurCore

@MainActor
private final class DeferredName {
    private var continuation: CheckedContinuation<String?, Never>?
    func name() async -> String? {
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilRequested() async {
        while continuation == nil { await Task.yield() }
    }
    func finish(_ name: String?) {
        continuation!.resume(returning: name)
        continuation = nil
    }
}

@main
@MainActor
struct BetaStateChecks {
    private struct Failure: Error { let message: String }
    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    private static func state() -> AppState {
        AppState(supportDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-beta-check-\(UUID())"))
    }
    private static func pair(_ state: AppState) -> (UUID, UUID) {
        let a = UUID(), b = UUID()
        for id in [a, b] {
            state.appendDictation(HistoryEntry(id: id, raw: "Example", polished: "Example",
                                              createdAt: Date(), appName: "Check", tags: []))
        }
        return (a, b)
    }
    private static func startNaming(_ state: AppState, folder: UUID, pair: (UUID, UUID), gate: DeferredName) -> Task<AppState.FolderNamingOutcome, Never> {
        state.nameFolderWithModel = { _, _ in await gate.name() }
        return Task { await state.nameGroupedFolder(folder, pair.0, pair.1) }
    }

    static func main() async throws {
        try await overlappingGroups()
        try await manualRenameWins()
        try await editingDraftWins()
        try await undoneRequestIsDiscarded()
        try await deletedRequestIsDiscarded()
        try await movedConversationInvalidatesRequest()
        try await mergePreservesPages()
        try await olderMergePreservesUndo()
        try await missingModelPromptsOnlyCurrentGroup()
        try detailReadsLiveEntry()
        print("10 beta state regression checks passed.")
    }

    private static func overlappingGroups() async throws {
        let s = state(), gate = DeferredName()
        let first = pair(s), second = pair(s)
        let folder = s.groupConversations(first.0, first.1)!.folderID
        let task = startNaming(s, folder: folder, pair: first, gate: gate)
        await gate.waitUntilRequested()
        let newer = s.groupConversations(second.0, second.1, name: "Second group")!.folderID
        gate.finish("First group")
        let outcome = await task.value
        try expect(outcome == .named, "The older folder should still be named")
        try expect(s.lastGroupingSummary == "Grouped 2 into Second group", "Late naming replaced the active undo label")
        s.undoLastGrouping()
        try expect(s.folders.contains { $0.id == folder }, "Undo removed the older folder")
        try expect(!s.folders.contains { $0.id == newer }, "Undo did not remove the newer empty folder")
    }

    private static func manualRenameWins() async throws {
        let s = state(), gate = DeferredName(), p = pairPlaceholder()
        // Use actual persisted entries in each isolated store.
        for entry in p { s.appendDictation(entry) }
        let folder = s.groupConversations(p[0].id, p[1].id)!.folderID
        let placeholder = s.folders.first { $0.id == folder }!.name
        let task = startNaming(s, folder: folder, pair: (p[0].id, p[1].id), gate: gate)
        await gate.waitUntilRequested()
        _ = s.renameFolder(folder, name: "My name")
        _ = s.renameFolder(folder, name: placeholder)
        gate.finish("Model name")
        let outcome = await task.value
        try expect(outcome == .discarded, "Manual rename must invalidate even when renamed back")
        try expect(s.folders.first { $0.id == folder }?.name == placeholder, "Model overwrote manual rename")
    }

    private static func pairPlaceholder() -> [HistoryEntry] {
        (0..<2).map { _ in HistoryEntry(id: UUID(), raw: "Example", polished: "Example", createdAt: Date(), appName: "Check", tags: []) }
    }

    private static func editingDraftWins() async throws {
        let s = state(), gate = DeferredName()
        let p = pair(s), folder = s.groupConversations(p.0, p.1)!.folderID
        let task = startNaming(s, folder: folder, pair: p, gate: gate)
        await gate.waitUntilRequested()
        s.cancelFolderNaming(folder) // The label invokes this before editing starts.
        gate.finish("Model name")
        try expect(await task.value == .discarded, "An uncommitted draft was overwritten or refocused")
        try expect(s.folders.first { $0.id == folder }?.name == "New Folder", "Draft's folder changed")
    }

    private static func undoneRequestIsDiscarded() async throws {
        let s = state(), gate = DeferredName()
        let p = pair(s), folder = s.groupConversations(p.0, p.1)!.folderID
        let task = startNaming(s, folder: folder, pair: p, gate: gate)
        await gate.waitUntilRequested()
        s.newPage(folderID: folder) // Keeps the folder alive after undo.
        s.undoLastGrouping()
        gate.finish("Model name")
        try expect(await task.value == .discarded, "Undone grouping accepted a late name")
        try expect(s.lastGroupingSummary == nil, "Late naming resurrected the undo banner")
    }

    private static func deletedRequestIsDiscarded() async throws {
        let s = state(), gate = DeferredName()
        let p = pair(s), folder = s.groupConversations(p.0, p.1)!.folderID
        let task = startNaming(s, folder: folder, pair: p, gate: gate)
        await gate.waitUntilRequested()
        s.deleteFolder(folder)
        gate.finish(nil)
        try expect(await task.value == .discarded, "Deleted folder requested rename focus")
    }

    private static func movedConversationInvalidatesRequest() async throws {
        let s = state(), gate = DeferredName()
        let p = pair(s), folder = s.groupConversations(p.0, p.1)!.folderID
        let task = startNaming(s, folder: folder, pair: p, gate: gate)
        await gate.waitUntilRequested()
        s.moveConversation(p.0, to: nil)
        gate.finish("Model name")
        try expect(await task.value == .discarded, "Changed group membership accepted a late name")
    }

    private static func mergePreservesPages() async throws {
        let s = state(), gate = DeferredName()
        s.createFolder("Existing")
        let target = s.folders.first { $0.name == "Existing" }!.id
        let p = pair(s), source = s.groupConversations(p.0, p.1)!.folderID
        let task = startNaming(s, folder: source, pair: p, gate: gate)
        await gate.waitUntilRequested()
        s.newPage(folderID: source)
        s.scratchpad = "Keep me with the conversations"
        let pageID = s.currentPageID
        gate.finish("Existing")
        try expect(await task.value == .named, "Merge failed")
        try expect(s.pages.first { $0.id == pageID }?.folderID == target, "Published page lost its folder")
        try expect(s.pages == s.notebook.pages, "Published pages are stale")
        try expect(s.currentPageID == pageID && s.scratchpad == "Keep me with the conversations", "Merge changed editor selection or text")
        s.undoLastGrouping()
        try expect(s.folders.contains { $0.id == target }, "Undo deleted preexisting destination")
        try expect(s.pages.first { $0.id == pageID }?.folderID == target, "Undo moved the merged page")
    }

    private static func olderMergePreservesUndo() async throws {
        let s = state(), gate = DeferredName()
        s.createFolder("Existing")
        let first = pair(s), second = pair(s)
        let source = s.groupConversations(first.0, first.1)!.folderID
        let task = startNaming(s, folder: source, pair: first, gate: gate)
        await gate.waitUntilRequested()
        let newer = s.groupConversations(second.0, second.1, name: "Newer")!.folderID
        gate.finish("Existing")
        try expect(await task.value == .named, "Older merge failed")
        try expect(s.lastGroupingSummary == "Grouped 2 into Newer", "Older merge changed undo label")
        s.undoLastGrouping()
        try expect(!s.folders.contains { $0.id == newer }, "Undo targeted the older merged group")
    }

    private static func missingModelPromptsOnlyCurrentGroup() async throws {
        let s = state()
        let first = pair(s), second = pair(s)
        let older = s.groupConversations(first.0, first.1)!.folderID
        let current = s.groupConversations(second.0, second.1)!.folderID
        try expect(await s.nameGroupedFolder(older, first.0, first.1) == .discarded, "Old fallback stole focus")
        try expect(await s.nameGroupedFolder(current, second.0, second.1) == .needsManualName, "Current fallback did not request a name")
    }

    private static func detailReadsLiveEntry() throws {
        let s = state(), p = pairPlaceholder()
        for entry in p { s.appendDictation(entry) }
        let sheet = ConversationDetailSheet(state: s, entryID: p[0].id, onClose: {}, onSend: {})
        s.addConversationTag("new-tag", id: p[0].id)
        try expect(sheet.entry?.tags == ["new-tag"], "Open detail did not read added tag")
        let folder = s.groupConversations(p[0].id, p[1].id, name: "Destination")!.folderID
        try expect(sheet.entry?.folderID == folder, "Open detail did not read moved folder")
        s.removeConversationTag("new-tag", id: p[0].id)
        try expect(sheet.entry?.tags.isEmpty == true, "Open detail did not read removed tag")
        s.deleteDictation(id: p[0].id)
        try expect(sheet.entry == nil, "Deleted conversation remained in detail")
    }
}
