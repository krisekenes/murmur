import SwiftUI
import MurmurCore

/// Folders are a shared namespace — the scratchpad files pages into the same folders
/// as conversations. The springboard doesn't make notes draggable, so it lists them
/// here rather than pretending the folder holds conversations only.
struct FolderNotesSection: View {
    @ObservedObject var state: AppState
    let folder: NoteFolder
    let onOpenScratchpad: () -> Void

    private var notes: [ScratchpadPage] {
        state.pages
            .filter { $0.folderID == folder.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALSO IN THIS FOLDER")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                ForEach(notes) { note in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(note.displayTitle)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Open") {
                            state.selectPage(note.id)
                            onOpenScratchpad()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }
            .padding(.top, 10)
        }
    }
}
