import SwiftUI
import MurmurCore

/// The feed pane: a searchable, date-grouped list of past dictations.
struct FeedView: View {
    @ObservedObject var state: AppState
    @Binding var search: String
    @Binding var selectedID: UUID?

    @State private var folderFilter = "all"
    @State private var tagFilter = ""
    @State private var showingFolders = false
    @State private var showingOrganizer = false

    private var allTags: [String] { Array(Set(state.historyEntries.flatMap(\.tags))).sorted() }
    private var folderLabel: String {
        if folderFilter == "all" { return "All folders" }
        return state.folders.first { $0.id.uuidString == folderFilter }?.name ?? "Unfiled"
    }

    private var filtered: [HistoryEntry] {
        state.historyEntries.filter { entry in
            (search.isEmpty || entry.polished.localizedCaseInsensitiveContains(search) || entry.tags.contains { $0.localizedCaseInsensitiveContains(search) })
            && (folderFilter == "all" || (folderFilter == "unfiled" && entry.folderID == nil) || entry.folderID?.uuidString == folderFilter)
            && (tagFilter.isEmpty || entry.tags.contains(tagFilter))
        }
    }

    private var groups: [(title: String, entries: [HistoryEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (title: Self.dayTitle(day, calendar: cal), entries: grouped[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider().opacity(0.5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if filtered.isEmpty {
                        Text(state.historyEntries.isEmpty ? "No conversations yet" : "No matching conversations")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 1)
                                ForEach(group.entries) { entry in
                                    FeedCard(
                                        entry: entry,
                                        isSelected: selectedID == entry.id,
                                        onTap: { selectedID = (selectedID == entry.id) ? nil : entry.id },
                                        onCopy: { copy(entry.polished) },
                                        onAppend: { state.appendToScratchpad(entry.polished) },
                                        onDelete: { state.deleteDictation(id: entry.id) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .sheet(isPresented: $showingFolders) { FolderManagerView(state: state) }
        .sheet(isPresented: $showingOrganizer) { SmartOrganizeView(state: state) }
        .onChange(of: state.folders) { _, folders in
            if folderFilter != "all" && folderFilter != "unfiled" && !folders.contains(where: { $0.id.uuidString == folderFilter }) { folderFilter = "all" }
        }
        .background(Color(red: 0.085, green: 0.085, blue: 0.095))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conversations").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(filtered.count)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Menu {
                    Button("All folders") { folderFilter = "all" }
                    Button("Unfiled") { folderFilter = "unfiled" }
                    ForEach(state.folders) { folder in
                        Button(folder.name) { folderFilter = folder.id.uuidString }
                    }
                    Divider()
                    Button("Manage folders…") { showingFolders = true }
                } label: { Label(folderLabel, systemImage: "folder").lineLimit(1) }
                Menu {
                    Button("All tags") { tagFilter = "" }
                    ForEach(allTags, id: \.self) { tag in
                        Button("#" + tag) { tagFilter = tag }
                    }
                } label: { Label(tagFilter.isEmpty ? "All tags" : tagFilter, systemImage: "tag").lineLimit(1) }
            }
            .menuStyle(.borderlessButton)
            .font(.system(size: 11))
            HStack {
                Button { showingOrganizer = true } label: {
                    Label("Smart organize", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(!state.historyEntries.contains { $0.folderID == nil })
                .help("Review folder suggestions for all unfiled conversations")
                Spacer()
            }.font(.system(size: 11))
            if state.organizedConversationCount > 0 {
                HStack {
                    Text("Filed \(state.organizedConversationCount)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo moves") { state.undoConversationOrganization() }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        .help("Undo the last batch of moves. Created folders stay available.")
                }.font(.caption)
            }
            if !search.isEmpty || folderFilter != "all" || !tagFilter.isEmpty {
                Button("Clear filters") { search = ""; folderFilter = "all"; tagFilter = "" }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        }.padding(12)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy"
        return f.string(from: day)
    }
}

/// One dictation card in the feed.
struct FeedCard: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onAppend: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.polished)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.tags.isEmpty {
                Text(entry.tags.map { "#" + $0 }.joined(separator: "  "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent.opacity(0.9))
                    .lineLimit(1)
            }
            HStack(spacing: 7) {
                Text(entry.createdAt, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                Text(entry.appName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                Spacer(minLength: 4)
                // Reserve the actions' space so highlighting never changes row layout.
                HStack(spacing: 7) {
                    iconButton("arrow.right.to.line", help: "Send to scratchpad", action: onAppend)
                    iconButton("doc.on.doc", help: "Copy", action: onCopy)
                }
                .opacity(hover || isSelected ? 1 : 0)
                .allowsHitTesting(hover || isSelected)
                .accessibilityHidden(!(hover || isSelected))
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(isSelected ? 0.10 : (hover ? 0.08 : 0.04))))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder((isSelected || hover) ? Theme.accent.opacity(isSelected ? 0.8 : 0.45) : .white.opacity(0.09),
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .contextMenu {
            Button("Send to Scratchpad", action: onAppend)
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Snapshot the proposals; applying rechecks current store state.
struct SmartOrganizeView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [FolderSuggestion] = []
    @State private var selected: Set<UUID> = []
    @State private var destinations: [UUID: String] = [:]
    @State private var unfiledCount = 0

    private var accepted: [FolderSuggestion] {
        suggestions.compactMap { suggestion in
            guard selected.contains(suggestion.id) else { return nil }
            let name = (destinations[suggestion.id] ?? suggestion.folderName).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return FolderSuggestion(id: suggestion.id, folderName: name, reason: suggestion.reason)
        }
    }

    private var newFolderCount: Int {
        let existing = Set(state.folders.map { $0.name.lowercased() })
        return Set(accepted.map { $0.folderName.lowercased() }).subtracting(existing).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Smart organize", systemImage: "sparkles").font(.title3.bold())
                Spacer()
                Text("\(unfiledCount) unfiled").foregroundStyle(.secondary)
            }
            Text("Review folder suggestions for your unfiled conversations. Edit a name to choose or create a folder.")
                .font(.callout).foregroundStyle(.secondary)
            if suggestions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No clear folder matches yet").font(.headline)
                    Text("Add a descriptive tag to a conversation, or file a few related conversations together, then try again.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Button("Select all") { selected = Set(suggestions.map(\.id)) }
                    Button("Deselect all") { selected = [] }
                    Spacer()
                    Text("\(unfiledCount - suggestions.count) without a clear match").foregroundStyle(.secondary)
                }.font(.caption)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            if let entry = state.historyEntries.first(where: { $0.id == suggestion.id }) {
                                suggestionRow(suggestion, entry: entry)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("\(accepted.count) moves · \(newFolderCount) new folders")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Organize \(accepted.count)") {
                    state.organizeConversations(accepted)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accepted.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580, height: 470)
        .onAppear {
            unfiledCount = state.historyEntries.filter { $0.folderID == nil }.count
            suggestions = SmartFolderOrganizer.suggestions(entries: state.historyEntries, folders: state.folders)
            selected = Set(suggestions.map(\.id))
            destinations = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.id, $0.folderName) })
        }
    }

    private func suggestionRow(_ suggestion: FolderSuggestion, entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Include conversation", isOn: Binding(
                get: { selected.contains(suggestion.id) },
                set: { if $0 { selected.insert(suggestion.id) } else { selected.remove(suggestion.id) } }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .accessibilityLabel("Include " + String(entry.polished.prefix(60)))
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.polished).font(.system(size: 12)).lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(Theme.accent)
                    TextField("Folder name", text: Binding(
                        get: { destinations[suggestion.id] ?? suggestion.folderName },
                        set: { destinations[suggestion.id] = $0 }
                    )).textFieldStyle(.roundedBorder)
                    Menu {
                        ForEach(state.folders) { folder in
                            Button(folder.name) { destinations[suggestion.id] = folder.name }
                        }
                    } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Choose an existing folder").disabled(state.folders.isEmpty)
                }
                Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12)
    }
}
