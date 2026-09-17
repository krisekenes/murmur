import SwiftUI
import MurmurCore

/// Beta springboard: conversations as tiles you drag together into folders.
/// Root shows unfiled conversations plus folder tiles; opening a folder shows its
/// conversations. Search flattens both, Finder-style.
struct SpringboardView: View {
    @ObservedObject var state: AppState
    @Binding var search: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var openFolderID: UUID?
    @State private var deletionTarget: NoteFolder?
    @State private var confirmingDeletion = false
    @State private var dropTargetID: UUID?
    @State private var renamingFolderID: UUID?
    private struct ConversationSelection: Identifiable { let id: UUID }
    @State private var detailSelection: ConversationSelection?
    @State private var openScratchpadAfterDetail = false
    @State private var showingScratchpad = false
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var groupingTrace: GroupingTrace?
    @State private var traceProgress: CGFloat = 0
    @State private var traceOpacity: Double = 0

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
            ZStack {
                grid
                    .id(isSearching ? "search" : (openFolderID?.uuidString ?? "root"))
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: openFolderID)
            footer
        }
        .background(NightSky())
        .coordinateSpace(name: "springboard")
        .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
        .overlay { groupingOverlay.allowsHitTesting(false).accessibilityHidden(true) }
        .clipped()
        .alert("Delete folder and contents?", isPresented: $confirmingDeletion, presenting: deletionTarget) { folder in
            Button("Cancel", role: .cancel) { deletionTarget = nil }
            Button("Delete everything", role: .destructive) {
                state.deleteFolderAndContents(folder.id)
                deletionTarget = nil
            }
        } message: { folder in
            Text("“\(folder.name)” and its \(state.conversationCount(inFolder: folder.id)) conversations and \(state.noteCount(inFolder: folder.id)) scratchpad pages will be permanently deleted. To keep them, choose Dissolve folder instead.")
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { groupingTrace = nil } }
        .sheet(item: $detailSelection, onDismiss: {
            if openScratchpadAfterDetail {
                openScratchpadAfterDetail = false
                showingScratchpad = true
            }
        }) { selection in
            ConversationDetailSheet(
                state: state,
                entryID: selection.id,
                onClose: { detailSelection = nil },
                onSend: {
                    openScratchpadAfterDetail = true
                    detailSelection = nil
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
                    if !visibleFolders.isEmpty {
                        sectionHeading("COLLECTIONS", count: visibleFolders.count)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(visibleFolders) { folder in folderTile(folder) }
                        }
                        .padding(.bottom, 28)
                    }
                    if !conversations.isEmpty {
                        sectionHeading(isSearching ? "MATCHING THOUGHTS" : (openFolderID == nil ? "UNFILED THOUGHTS" : "CONVERSATIONS"), count: conversations.count)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(conversations) { entry in conversationTile(entry) }
                        }
                    }
                }
                if let folder = openFolder, !isSearching {
                    FolderNotesSection(state: state, folder: folder,
                                       onOpenScratchpad: { showingScratchpad = true })
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: visibleFolders.map(\.id))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: conversations.map(\.id))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dropping on empty canvas inside a folder takes the conversation back out.
        .dropDestination(for: ConversationRef.self) { refs, _ in
            unfileDropped(refs, requiringOpenFolder: true)
        }
    }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 184, maximum: 260), spacing: 22)] }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).tracking(1.8)
            Text("\(count)").foregroundStyle(Theme.muted.opacity(0.65))
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(Theme.muted)
        .padding(.bottom, 14)
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
            onOpen: { detailSelection = ConversationSelection(id: entry.id) },
            onRename: { state.setPrimaryConversationTag($0, id: entry.id) }
        )
        .background(tileFrame(entry.id))
        .dropDestination(for: ConversationRef.self) { refs, _ in
            guard let ref = refs.first, ref.id != entry.id else { return false }
            guard let result = state.groupConversations(ref.id, entry.id) else { return false }
            showGroupingTrace(from: ref.id, to: entry.id)
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
                    let outcome = await state.nameGroupedFolder(folderID, dragged, dropped)
                    if case .needsManualName = outcome { renamingFolderID = folderID }
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
            onRenameEnded: { renamingFolderID = nil },
            onRenameBegan: { state.cancelFolderNaming(folder.id) }
        )
        .background(tileFrame(folder.id))
        .contextMenu { folderActions(folder) }
        .dropDestination(for: FolderDrop.self) { refs, _ in
            guard let ref = refs.first else { return false }
            switch ref {
            case .conversation(let conversation):
                guard state.historyEntries.contains(where: { $0.id == conversation.id && $0.folderID != folder.id }) else { return false }
                state.fileConversation(conversation.id, into: folder.id)
                showGroupingTrace(from: conversation.id, to: folder.id)
            case .folder(let source):
                guard state.mergeFolders(source.id, into: folder.id) else { return false }
                showGroupingTrace(from: source.id, to: folder.id)
            }
            return true
        } isTargeted: { targeted in
            if targeted { dropTargetID = folder.id }
            else if dropTargetID == folder.id { dropTargetID = nil }
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private func folderActions(_ folder: NoteFolder) -> some View {
        Button("Open folder", systemImage: "folder") { openFolderID = folder.id }
        Button("Rename…", systemImage: "pencil") {
            state.cancelFolderNaming(folder.id)
            openFolderID = nil
            renamingFolderID = folder.id
        }
        Button("New constellation", systemImage: "sparkles") { state.regenerateConstellation(folder.id) }
        Menu("Merge into…") {
            ForEach(state.folders.filter { $0.id != folder.id }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }) { destination in
                Button(destination.name) {
                    if state.mergeFolders(folder.id, into: destination.id), openFolderID == folder.id {
                        openFolderID = destination.id
                    }
                }
            }
        }
        .disabled(state.folders.count < 2)
        Divider()
        Button("Dissolve folder · keep contents", systemImage: "square.stack.3d.up.slash") {
            state.deleteFolder(folder.id)
        }
        Button("Delete folder and contents…", systemImage: "trash", role: .destructive) {
            deletionTarget = folder
            confirmingDeletion = true
        }
    }

    private var breadcrumb: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if let folder = openFolder, !isSearching {
                    Button { openFolderID = nil } label: { Label("All", systemImage: "chevron.left") }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .dropDestination(for: ConversationRef.self) { refs, _ in
                            unfileDropped(refs, requiringOpenFolder: false)
                        }
                    Text(folder.name).font(.system(size: 30, weight: .regular, design: .serif))
                        .lineLimit(1)
                } else {
                    if isSearching {
                        Text("Search results")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
            Spacer()
            if let folder = openFolder, !isSearching {
                Constellation(seed: ConstellationStyle.seed(for: folder.effectiveConstellationID), tint: ConstellationStyle.tint(for: folder.id))
                    .frame(width: 90, height: 55)
                Menu { folderActions(folder) } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Folder options")
            } else {
                Text("\(isSearching ? conversations.count : state.historyEntries.count) conversations")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 8)
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
        .padding(.horizontal, 28)
        .padding(.vertical, 7)
        .background(.white.opacity(0.04))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Constellation(seed: 0xA574A2026).frame(width: 150, height: 80)
            Text(isSearching ? "No matching conversations" : (openFolderID == nil ? "No conversations yet" : "No conversations in this folder"))
                .font(.system(size: 25, weight: .regular, design: .serif)).foregroundStyle(Theme.ink)
            Text(isSearching ? "Try another word or tag." : (openFolderID == nil ? "Hold \(state.hotkey == .fn ? "Fn" : "Right Option") to record." : "Drag conversations into this folder to add them."))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            if isSearching {
                Button("Clear search") { search = "" }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            VoiceSignal(phase: state.phase, level: state.inputLevel)
            VStack(alignment: .leading, spacing: 4) {
                Text(recordingLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                Text("Drag thoughts together to make a collection")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { showingScratchpad = true } label: {
                Label("Scratchpad", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Theme.midnight.opacity(0.85))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    private var recordingLabel: String {
        switch state.phase {
        case .listening(let locked): return locked ? "Listening, hands-free" : "Listening to your thought…"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing your words…"
        case .downloading: return "Preparing models…"
        case .error: return "Check the message above"
        case .idle: return "Hold \(state.hotkey == .fn ? "Fn" : "Right Option") to capture a thought"
        }
    }

    private func tileFrame(_ id: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: TileFramesKey.self, value: [id: proxy.frame(in: .named("springboard"))])
        }
    }

    @ViewBuilder private var groupingOverlay: some View {
        if let trace = groupingTrace, !reduceMotion {
            Path { path in path.move(to: trace.from); path.addLine(to: trace.to) }
                .trim(from: 0, to: traceProgress)
                .stroke(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .shadow(color: Theme.accent.opacity(0.6), radius: 5)
                .opacity(traceOpacity)
            Circle().fill(Theme.accent)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.accent, radius: 8)
                .position(x: trace.from.x + (trace.to.x - trace.from.x) * traceProgress,
                          y: trace.from.y + (trace.to.y - trace.from.y) * traceProgress)
                .opacity(traceOpacity)
        }
    }

    private func showGroupingTrace(from source: UUID, to target: UUID) {
        guard !reduceMotion, let a = tileFrames[source], let b = tileFrames[target] else { return }
        let trace = GroupingTrace(from: CGPoint(x: a.midX, y: a.minY + Theme.tileHeight / 2),
                                  to: CGPoint(x: b.midX, y: b.minY + Theme.tileHeight / 2))
        groupingTrace = trace
        traceProgress = 0
        traceOpacity = 1
        Task { @MainActor in
            // Give the new overlay its initial frame before drawing the connection.
            try? await Task.sleep(for: .milliseconds(20))
            guard groupingTrace?.id == trace.id else { return }
            withAnimation(.easeOut(duration: 0.3)) { traceProgress = 1 }
            try? await Task.sleep(for: .milliseconds(320))
            guard groupingTrace?.id == trace.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { traceOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(260))
            if groupingTrace?.id == trace.id { groupingTrace = nil }
        }
    }

}

private struct GroupingTrace {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
}

private struct TileFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// Observe the store inside the sheet; its selection holds only an ID, never a
/// snapshot whose tags and folder can go stale while the sheet remains open.
struct ConversationDetailSheet: View {
    @ObservedObject var state: AppState
    let entryID: UUID
    let onClose: () -> Void
    let onSend: () -> Void

    var entry: HistoryEntry? { state.historyEntries.first { $0.id == entryID } }

    var body: some View {
        Group {
            if let entry {
                DictationDetailView(
                    state: state,
                    entry: entry,
                    onClose: onClose,
                    onCopy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.polished.isEmpty ? entry.raw : entry.polished, forType: .string)
                    },
                    onSend: {
                        state.appendToScratchpad(entry.polished.isEmpty ? entry.raw : entry.polished)
                        onSend()
                    },
                    onDelete: { state.deleteDictation(id: entryID); onClose() }
                )
            }
        }
        .onChange(of: entry == nil) { _, missing in if missing { onClose() } }
    }
}
