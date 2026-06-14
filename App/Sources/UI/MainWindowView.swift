import SwiftUI

/// Murmur's primary window: a sidebar split of the dictation feed (left) and the
/// editable scratchpad (right), with a top bar carrying search and live status.
struct MainWindowView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.5)
            HSplitView {
                FeedView(state: state, search: $search, selectedID: $selectedID)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 440)
                rightPane
                    .frame(minWidth: 380)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }

    /// The right pane shows the selected dictation for reading, or the scratchpad
    /// when nothing is selected. Selecting never disturbs the scratchpad note.
    @ViewBuilder private var rightPane: some View {
        if let id = selectedID, let entry = state.historyEntries.first(where: { $0.id == id }) {
            DictationDetailView(
                entry: entry,
                onClose: { selectedID = nil },
                onCopy: { copy(entry.polished) },
                onSend: { state.appendToScratchpad(entry.polished); selectedID = nil },
                onDelete: { state.deleteDictation(id: id); selectedID = nil }
            )
        } else {
            ScratchpadView(state: state)
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Murmur").font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(searchFocused ? Theme.accent.opacity(0.9) : Color.secondary.opacity(0.7))
                TextField("Search dictations", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(maxWidth: 220)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(searchFocused ? Theme.accent.opacity(0.55) : .white.opacity(0.08))
            )
            .animation(.easeOut(duration: 0.15), value: searchFocused)

            StatusDot(phase: state.phase)

            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}
