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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(spacing: 8) {
            preview
            RenameableLabel(
                text: label,
                editSeed: entry.tags.first ?? "",
                font: .system(size: 12, weight: .medium),
                color: entry.tags.isEmpty ? Theme.muted : Theme.accent.opacity(0.9),
                beginsEditing: false,
                onCommit: onRename,
                onEditingEnded: {}
            )
            Text(entry.appName)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var preview: some View {
        Group {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(Theme.accent.opacity(0.65))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
                Text(previewText)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.tileHeight)
            .background(RoundedRectangle(cornerRadius: 17).fill(Theme.tile))
            .background(RoundedRectangle(cornerRadius: 17).fill(Theme.accent.opacity(0.01))
                .shadow(color: Theme.accent.opacity(hover || isDropTarget ? 0.13 : 0), radius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(isDropTarget ? Theme.accent : (hover ? Theme.accent.opacity(0.45) : .white.opacity(0.09)), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        // Keep the preview as a drag surface. A nested Button consumes the
        // mouse-down before the enclosing tile can begin its drag session.
        .onTapGesture(perform: onOpen)
        .draggable(ConversationRef(entry: entry))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hover)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isDropTarget)
        .accessibilityLabel(Text("Open conversation: " + String(previewText.prefix(80))))
    }
}
