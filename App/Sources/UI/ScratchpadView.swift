import SwiftUI
import MurmurCore

/// The scratchpad pane: a large editable note you dictate into or type. Persists
/// via AppState.scratchpad (backed by NotebookStore).
struct ScratchpadView: View {
    @ObservedObject var state: AppState

    @State private var showingBrowser = false
    @State private var showingFolders = false
    @State private var search = ""
    @State private var folderFilter = "all"
    @State private var tagFilter = ""
    @State private var newTag = ""

    private var currentPage: ScratchpadPage? { state.pages.first { $0.id == state.currentPageID } }
    private var allTags: [String] { Array(Set(state.pages.flatMap(\.tags))).sorted() }
    private var suggestions: [String] {
        NoteTagger.suggestions(for: state.scratchpad, existing: currentPage?.tags ?? [], vocabulary: allTags)
    }
    private var filteredPages: [ScratchpadPage] {
        state.pages.filter { page in
            (folderFilter == "all" || (folderFilter == "unfiled" && page.folderID == nil) || page.folderID?.uuidString == folderFilter)
            && (tagFilter.isEmpty || page.tags.contains(tagFilter))
            && (search.isEmpty || page.content.localizedCaseInsensitiveContains(search) || page.tags.contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var currentTitle: String {
        state.pages.first(where: { $0.id == state.currentPageID })?.displayTitle ?? "Untitled"
    }

    /// Selecting in the inline picker switches pages (and shows a checkmark on the current).
    private var pageSelection: Binding<UUID> {
        Binding(get: { state.currentPageID }, set: { state.selectPage($0) })
    }

    private func pageMenuLabel(_ page: ScratchpadPage) -> String {
        "\(page.displayTitle)  ·  \(page.updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var pageHeader: some View {
        HStack(spacing: 8) {
            Button { showingBrowser.toggle() } label: {
                Label("Browse", systemImage: "books.vertical")
            }
            .help("Browse notes by folder or tag")

            Menu {
                Picker("Pages", selection: pageSelection) {
                    ForEach(state.pages) { page in
                        Text(pageMenuLabel(page)).tag(page.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button(role: .destructive) { state.deleteCurrentPage() } label: {
                    Label("Delete this page", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Text("\(state.pages.count) page\(state.pages.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button { state.newPage(folderID: currentPage?.folderID) } label: { Label("New page", systemImage: "plus") }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            if showingBrowser { noteBrowser; Divider().opacity(0.5) }
            organizationHeader
            Divider().opacity(0.5)
            ZStack(alignment: .topLeading) {
                if state.scratchpad.isEmpty {
                    Text("Dictate or type here — everything you say lands and stays editable.")
                        .font(.system(size: 13))
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: 340, alignment: .leading)
                        .padding(.horizontal, 19)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $state.scratchpad)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(14)
            }

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Text("\(state.scratchpad.split(whereSeparator: { $0.isWhitespace }).count) words")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: copy) { Label("Copy", systemImage: "doc.on.doc") }
                Button(role: .destructive, action: { state.scratchpad = "" }) { Label("Clear", systemImage: "trash") }
                    .disabled(state.scratchpad.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(10)
        }
        .sheet(isPresented: $showingFolders) { FolderManagerView(state: state) }
        .onChange(of: state.currentPageID) { _, _ in newTag = "" }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private var organizationHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("Unfiled") { state.movePage(to: nil) }
                    ForEach(state.folders) { folder in
                        Button(folder.name) { state.movePage(to: folder.id) }
                    }
                    Divider()
                    Button("Manage folders…") { showingFolders = true }
                } label: {
                    Label(state.folders.first { $0.id == currentPage?.folderID }?.name ?? "Unfiled", systemImage: "folder")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 160, alignment: .leading)
                Spacer()
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit(addTag)
                Button(action: addTag) { Image(systemName: "plus") }
                    .help("Add tag")
                    .disabled(NoteTagger.normalize(newTag).isEmpty)
            }
            if !(currentPage?.tags.isEmpty ?? true) {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(currentPage?.tags ?? [], id: \.self) { tag in
                            Button { state.removeTag(tag) } label: {
                                HStack(spacing: 4) { Text("#" + tag); Image(systemName: "xmark").font(.system(size: 8)) }
                            }
                            .help("Remove tag " + tag)
                            .accessibilityLabel("Remove tag " + tag)
                        }
                    }
                }
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        Text("Suggested").foregroundStyle(.secondary)
                        ForEach(suggestions, id: \.self) { tag in
                            Button("+ " + tag) { state.addTag(tag) }
                                .help("Add suggested tag " + tag)
                        }
                    }
                }
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .buttonStyle(.bordered)
        .padding(.horizontal, 13)
        .padding(.bottom, 10)
    }

    private var noteBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scratchpad pages").font(.headline)
                Spacer()
                Button("Manage folders…") { showingBrowser = false; showingFolders = true }
            }
            TextField("Search pages or tags", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Folder", selection: $folderFilter) {
                    Text("All pages").tag("all")
                    Text("Unfiled").tag("unfiled")
                    ForEach(state.folders) { Text($0.name).tag($0.id.uuidString) }
                }
                Picker("Tag", selection: $tagFilter) {
                    Text("All tags").tag("")
                    ForEach(allTags, id: \.self) { Text("#" + $0).tag($0) }
                }
            }
            if filteredPages.isEmpty {
                Text("No pages match these filters.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredPages) { page in
                            Button {
                                state.selectPage(page.id)
                                showingBrowser = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(page.displayTitle).lineLimit(1)
                                        Text(page.tags.map { "#" + $0 }.joined(separator: "  "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if page.id == state.currentPageID { Image(systemName: "checkmark") }
                                }
                                .padding(8)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Button("New page") {
                state.newPage(folderID: UUID(uuidString: folderFilter))
                showingBrowser = false
            }
        }
        .padding(16)
        .frame(height: 230)
        .onAppear {
            if !allTags.contains(tagFilter) { tagFilter = "" }
            if folderFilter != "all" && folderFilter != "unfiled" && !state.folders.contains(where: { $0.id.uuidString == folderFilter }) { folderFilter = "all" }
        }
    }

    private func addTag() { state.addTag(newTag); newTag = "" }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.scratchpad, forType: .string)
    }
}

/// Shared folder management for conversations and scratchpad pages.
struct FolderManagerView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var folderName = ""
    @State private var editingFolderID: UUID?
    @State private var folderError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Folders").font(.headline)
            Text("Deleting a folder keeps its conversations and pages in Unfiled.").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(state.folders) { folder in
                    HStack {
                        Label(folder.name, systemImage: "folder")
                        Spacer()
                        Button("Rename") { editingFolderID = folder.id; folderName = folder.name; folderError = "" }
                        Button(role: .destructive) {
                            state.deleteFolder(folder.id)
                            if editingFolderID == folder.id { editingFolderID = nil; folderName = "" }
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete folder " + folder.name)
                    }
                }
            }.frame(height: 180)
            HStack {
                TextField(editingFolderID == nil ? "New folder name" : "Folder name", text: $folderName)
                    .textFieldStyle(.roundedBorder).onSubmit(saveFolder)
                Button(editingFolderID == nil ? "Create" : "Save", action: saveFolder)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingFolderID != nil {
                    Button("Cancel") { editingFolderID = nil; folderName = ""; folderError = "" }
                }
            }
            if !folderError.isEmpty { Text(folderError).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 440)
    }

    private func saveFolder() {
        guard !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let id = editingFolderID {
            guard state.renameFolder(id, name: folderName) else {
                folderError = "Choose a unique folder name."
                return
            }
        } else { state.createFolder(folderName) }
        editingFolderID = nil
        folderName = ""
        folderError = ""
    }

}
