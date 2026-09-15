import SwiftUI
import MurmurCore

/// Beta springboard: conversations as tiles you drag together into folders.
/// Root shows unfiled conversations plus folder tiles; opening a folder shows its
/// conversations. Search flattens both, Finder-style.
struct SpringboardView: View {
    @ObservedObject var state: AppState
    @Binding var search: String

    @State private var openFolderID: UUID?
    @State private var dropTargetID: UUID?
    @State private var renamingFolderID: UUID?
    @State private var detailEntry: HistoryEntry?
    @State private var showingScratchpad = false

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var openFolder: NoteFolder? {
        openFolderID.flatMap { id in state.folders.first { $0.id == id } }
    }

    private func matches(_ entry: HistoryEntry) -> Bool {
        entry.polished.localizedCaseInsensitiveContains(search)
            || entry.raw.localizedCaseInsensitiveContains(search)
            || entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    /// `history.entries` is newest-first, so these stay newest-first for free.
    private var conversations: [HistoryEntry] {
        if isSearching { return state.historyEntries.filter(matches) }
        if let openFolderID { return state.historyEntries.filter { $0.folderID == openFolderID } }
        return state.historyEntries.filter { $0.folderID == nil }
    }

    /// Folders are hidden while searching so results read as one flat list.
    private var visibleFolders: [NoteFolder] {
        guard !isSearching, openFolderID == nil else { return [] }
        return state.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            if let summary = state.lastGroupingSummary { undoBar(summary) }
            Divider().opacity(0.5)
            grid
            footer
        }
        .background(Theme.canvas)
        .sheet(item: $detailEntry) { entry in
            DictationDetailView(
                state: state,
                entry: entry,
                onClose: { detailEntry = nil },
                onCopy: { copy(entry.polished.isEmpty ? entry.raw : entry.polished) },
                onSend: {
                    state.appendToScratchpad(entry.polished)
                    detailEntry = nil
                    showingScratchpad = true
                },
                onDelete: {
                    state.deleteDictation(id: entry.id)
                    detailEntry = nil
                }
            )
            .frame(minWidth: 460, minHeight: 420)
        }
        .sheet(isPresented: $showingScratchpad) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { showingScratchpad = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(10)
                ScratchpadView(state: state)
            }
            .frame(minWidth: 520, minHeight: 440)
        }
        .onChange(of: state.folders) { _, folders in
            // The open folder can be deleted from the scratchpad. Pop back out.
            if let id = openFolderID, !folders.contains(where: { $0.id == id }) { openFolderID = nil }
        }
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if conversations.isEmpty && visibleFolders.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 18)],
                              alignment: .leading, spacing: 20) {
                        ForEach(visibleFolders) { folder in folderTile(folder) }
                        ForEach(conversations) { entry in conversationTile(entry) }
                    }
                }
                if let folder = openFolder, !isSearching {
                    FolderNotesSection(state: state, folder: folder,
                                       onOpenScratchpad: { showingScratchpad = true })
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dropping on empty canvas inside a folder takes the conversation back out.
        .dropDestination(for: ConversationRef.self) { refs, _ in
            unfileDropped(refs, requiringOpenFolder: true)
        }
    }

    /// Dragging a tile out of an open folder unfiles it. Guarded on `!isSearching`
    /// because the flattened search grid is not "inside" any folder — the remembered
    /// `openFolderID` would otherwise unfile a conversation from a folder you cannot
    /// even see. One helper so the guard cannot drift between drop sites.
    private func unfileDropped(_ refs: [ConversationRef], requiringOpenFolder: Bool) -> Bool {
        guard !isSearching, let ref = refs.first else { return false }
        if requiringOpenFolder && openFolderID == nil { return false }
        state.moveConversation(ref.id, to: nil)
        return true
    }

    private func conversationTile(_ entry: HistoryEntry) -> some View {
        ConversationTile(
            entry: entry,
            isDropTarget: dropTargetID == entry.id,
            onOpen: { detailEntry = entry },
            onRename: { state.setPrimaryConversationTag($0, id: entry.id) }
        )
        .draggable(ConversationRef(entry: entry))
        .dropDestination(for: ConversationRef.self) { refs, _ in
            guard let ref = refs.first, ref.id != entry.id else { return false }
            guard let result = state.groupConversations(ref.id, entry.id) else { return false }
            if result.shouldPromptForName {
                // The name field can only take focus once the folder's tile renders, and a
                // flattened search grid hides folder tiles — so surface the root grid.
                search = ""
                openFolderID = nil
                // Let the model name it first. Focusing the field now would race the
                // rename and overwrite whatever was typed, so the field only takes
                // focus if the model declines to answer.
                let folderID = result.folderID
                let (dragged, dropped) = (ref.id, entry.id)
                Task {
                    let named = await state.nameGroupedFolder(folderID, dragged, dropped)
                    if !named { renamingFolderID = folderID }
                }
            } else if !isSearching {
                // Both tiles moved into the folder, so the open folder no longer shows them.
                // While searching, openFolderID is only a memo for when search clears.
                openFolderID = nil
            }
            return true
        } isTargeted: { targeted in
            if targeted { dropTargetID = entry.id }
            else if dropTargetID == entry.id { dropTargetID = nil }
        }
    }

    private func folderTile(_ folder: NoteFolder) -> some View {
        FolderTile(
            folder: folder,
            previews: state.historyEntries
                .filter { $0.folderID == folder.id }
                .prefix(4)
                .map { $0.polished.isEmpty ? $0.raw : $0.polished },
            conversationCount: state.conversationCount(inFolder: folder.id),
            noteCount: state.noteCount(inFolder: folder.id),
            isDropTarget: dropTargetID == folder.id,
            beginsRenaming: renamingFolderID == folder.id,
            onOpen: { openFolderID = folder.id },
            onRename: { _ = state.renameFolder(folder.id, name: $0) },
            onRenameEnded: { renamingFolderID = nil }
        )
        .dropDestination(for: ConversationRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            state.fileConversation(ref.id, into: folder.id)
            return true
        } isTargeted: { targeted in
            if targeted { dropTargetID = folder.id }
            else if dropTargetID == folder.id { dropTargetID = nil }
        }
    }

    // MARK: Chrome

    @ViewBuilder private var breadcrumb: some View {
        if isSearching {
            header { Text("Results for \u{201C}\(search)\u{201D}") }
        } else if let folder = openFolder {
            header {
                Button { openFolderID = nil } label: {
                    Label("All", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                // Dragging a tile onto the breadcrumb takes it out of the folder.
                .dropDestination(for: ConversationRef.self) { refs, _ in
                    unfileDropped(refs, requiringOpenFolder: false)
                }
                Text("/").foregroundStyle(.tertiary)
                Text(folder.name).fontWeight(.semibold)
            }
        } else {
            header { Text("All conversations") }
        }
    }

    private func header<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
            Spacer()
            Text("\(conversations.count)").foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 22)
        .frame(height: 38)
    }

    private func undoBar(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus").foregroundStyle(Theme.accent)
            Text(summary)
            Text("·").foregroundStyle(.tertiary)
            Button("Undo") { state.undoLastGrouping() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(.white.opacity(0.04))
    }

    private var emptyState: some View {
        Text(state.historyEntries.isEmpty ? "No conversations yet" : "No matching conversations")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    private var footer: some View {
        HStack {
            Text("Drag one conversation onto another to group them")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button { showingScratchpad = true } label: {
                Label("Scratchpad", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
