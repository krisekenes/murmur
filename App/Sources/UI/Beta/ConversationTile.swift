import SwiftUI
import MurmurCore

/// One conversation on the springboard: a preview of what was actually said, with
/// a renameable primary tag beneath it the way a file sits under its name.
struct ConversationTile: View {
    let entry: HistoryEntry
    let isDropTarget: Bool
    let onOpen: () -> Void
    let onRename: (String) -> Void

    @State private var hover = false

    private var previewText: String {
        let text = entry.polished.isEmpty ? entry.raw : entry.polished
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Untagged conversations fall back to a time stamp until you name them.
    private var label: String {
        entry.tags.first.map { "#" + $0 }
            ?? entry.createdAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 6) {
            preview
            RenameableLabel(
                text: label,
                editSeed: entry.tags.first ?? "",
                font: .system(size: 10),
                color: entry.tags.isEmpty ? Color.secondary : Theme.accent.opacity(0.9),
                beginsEditing: false,
                onCommit: onRename,
                onEditingEnded: {}
            )
        }
        .frame(width: 132)
    }

    private var preview: some View {
        Text(previewText)
            .font(.system(size: 10))
            .lineSpacing(1.5)
            .foregroundStyle(.primary.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .frame(width: 118, height: 92, alignment: .topLeading)
            .clipped()
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(hover ? 0.09 : 0.05)))
            .overlay(alignment: .bottom) {
                // Fade the clipped text instead of slicing a line of glyphs in half.
                LinearGradient(colors: [.clear, Theme.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .allowsHitTesting(false)
            }
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
            .accessibilityLabel(Text("Conversation: " + String(previewText.prefix(80))))
    }
}
