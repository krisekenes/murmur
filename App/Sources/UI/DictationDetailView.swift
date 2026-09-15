import SwiftUI
import MurmurCore

/// Read view for a selected dictation, shown in the right pane in place of the
/// scratchpad. Non-destructive — the scratchpad returns when this is dismissed.
struct DictationDetailView: View {
    @ObservedObject var state: AppState
    @State private var newTag = ""
    @State private var showingFolders = false
    let entry: HistoryEntry
    let onClose: () -> Void
    let onCopy: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .semibold))
                    Text(entry.appName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to scratchpad")
            }
            .padding(14)

            organization
            Divider().opacity(0.5)

            ScrollView {
                Text(entry.polished)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Spacer()
                Button(action: onSend) { Label("Send to Scratchpad", systemImage: "arrow.right.to.line") }
                Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(10)
        }
        .sheet(isPresented: $showingFolders) { FolderManagerView(state: state) }
        .onChange(of: entry.id) { _, _ in newTag = "" }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private var organization: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    Button("Unfiled") { state.moveConversation(entry.id, to: nil) }
                    ForEach(state.folders) { folder in
                        Button(folder.name) { state.moveConversation(entry.id, to: folder.id) }
                    }
                    Divider()
                    Button("Manage folders…") { showingFolders = true }
                } label: {
                    Label(state.folders.first { $0.id == entry.folderID }?.name ?? "Unfiled", systemImage: "folder")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                Spacer()
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.roundedBorder).frame(width: 120).onSubmit(addTag)
                Button(action: addTag) { Image(systemName: "plus") }
                    .help("Add tag").disabled(NoteTagger.normalize(newTag).isEmpty)
            }
            if !entry.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Button { state.removeConversationTag(tag, id: entry.id) } label: {
                                HStack(spacing: 4) { Text("#" + tag); Image(systemName: "xmark").font(.system(size: 8)) }
                            }
                            .help("Remove tag " + tag)
                            .accessibilityLabel("Remove tag " + tag)
                        }
                    }
                }
            }
            Text("Tags are added automatically from the text. Add or remove them here.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func addTag() { state.addConversationTag(newTag, id: entry.id); newTag = "" }

}
