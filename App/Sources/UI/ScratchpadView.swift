import SwiftUI
import MurmurCore

/// The scratchpad pane: a large editable note you dictate into or type. Persists
/// via AppState.scratchpad (backed by ScratchpadStore).
struct ScratchpadView: View {
    @ObservedObject var state: AppState

    private var currentTitle: String {
        state.pages.first(where: { $0.id == state.currentPageID })?.displayTitle ?? "Untitled"
    }

    private var pageHeader: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(state.pages) { page in
                    Button { state.selectPage(page.id) } label: {
                        Label(page.displayTitle,
                              systemImage: page.id == state.currentPageID ? "checkmark" : "doc.text")
                    }
                }
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

            Button { state.newPage() } label: { Label("New page", systemImage: "plus") }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
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
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.scratchpad, forType: .string)
    }
}
