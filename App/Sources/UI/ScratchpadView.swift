import SwiftUI

/// The scratchpad pane: a large editable note you dictate into or type. Persists
/// via AppState.scratchpad (backed by ScratchpadStore).
struct ScratchpadView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
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
