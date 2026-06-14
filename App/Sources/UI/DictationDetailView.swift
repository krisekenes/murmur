import SwiftUI
import MurmurCore

/// Read view for a selected dictation, shown in the right pane in place of the
/// scratchpad. Non-destructive — the scratchpad returns when this is dismissed.
struct DictationDetailView: View {
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
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }
}
