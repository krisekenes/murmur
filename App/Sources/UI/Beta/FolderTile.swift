import SwiftUI
import MurmurCore

/// A folder on the springboard, identified by a stable constellation and color.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tint: Color { ConstellationStyle.tint(for: folder.id) }

    private var countLabel: String {
        noteCount == 0
            ? "\(conversationCount) conversation\(conversationCount == 1 ? "" : "s")"
            : "\(conversationCount) conversations · \(noteCount) page\(noteCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 8) {
            previewGrid
            RenameableLabel(
                text: folder.name,
                editSeed: folder.name,
                font: .system(size: 12, weight: .medium),
                color: Theme.ink,
                beginsEditing: beginsRenaming,
                onCommit: onRename,
                onEditingEnded: onRenameEnded,
                onEditingBegan: onRenameBegan
            )
            Text(countLabel)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewGrid: some View {
        Group {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("FOLDER").tracking(1.8)
                    Spacer()
                    Constellation(seed: ConstellationStyle.seed(for: folder.effectiveConstellationID), tint: tint)
                        .frame(width: 64, height: 22)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tint.opacity(0.85))
                if previews.isEmpty {
                    Text(noteCount > 0 ? "A place for your notes" : "Drop conversations here")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(previews.prefix(3).enumerated()), id: \.offset) { _, preview in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(tint.opacity(0.8)).frame(width: 4, height: 4).padding(.top, 5)
                            Text(preview).font(.system(size: 11)).foregroundStyle(Theme.ink.opacity(0.9))
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.055)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .background(RoundedRectangle(cornerRadius: 17).fill(Theme.tile))
            .overlay(RoundedRectangle(cornerRadius: 17).fill(
                LinearGradient(colors: [tint.opacity(0.055), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 17)
                .strokeBorder(tint.opacity(isDropTarget ? 1 : (hover ? 0.55 : 0.23)), lineWidth: 1))
            .shadow(color: tint.opacity(hover || isDropTarget ? 0.12 : 0), radius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .onTapGesture(perform: onOpen)
        .draggable(FolderRef(id: folder.id))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .help("Drag onto another folder to merge their contents")
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hover)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isDropTarget)
        .accessibilityLabel(Text("Open folder \(folder.name), \(countLabel)"))
    }
}
