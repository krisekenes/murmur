import SwiftUI
import MurmurCore

/// A folder on the springboard: a 2x2 of the newest conversations inside, iOS-style.
/// Counts include scratchpad pages, because NoteFolder is a namespace shared with
/// the notebook and a conversations-only count would misreport the folder.
struct FolderTile: View {
    let folder: NoteFolder
    /// Up to four conversation previews, newest first.
    let previews: [String]
    let conversationCount: Int
    let noteCount: Int
    let isDropTarget: Bool
    /// Set right after a drop created this folder with a fallback name.
    let beginsRenaming: Bool
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onRenameEnded: () -> Void
    let onRenameBegan: () -> Void

    @State private var hover = false

    private var countLabel: String {
        noteCount == 0
            ? "\(conversationCount)"
            : "\(conversationCount) · \(noteCount) note\(noteCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 6) {
            previewGrid
            RenameableLabel(
                text: folder.name,
                editSeed: folder.name,
                font: .system(size: 10, weight: .medium),
                color: .primary,
                beginsEditing: beginsRenaming,
                onCommit: onRename,
                onEditingEnded: onRenameEnded,
                onEditingBegan: onRenameBegan
            )
            Text(countLabel)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(width: 132)
    }

    private var previewGrid: some View {
        VStack(spacing: 5) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { column in
                        miniature(at: row * 2 + column)
                    }
                }
            }
        }
        .padding(9)
        .frame(width: 118, height: 92)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(hover ? 0.10 : 0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(isDropTarget ? Theme.accent : .white.opacity(0.09),
                              lineWidth: isDropTarget ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .accessibilityLabel(Text("Folder \(folder.name), \(countLabel)"))
    }

    private func miniature(at index: Int) -> some View {
        Group {
            if index < previews.count {
                Text(previews[index])
                    .font(.system(size: 5))
                    .lineSpacing(0.5)
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.10)))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.04))
            }
        }
        .clipped()
    }
}
