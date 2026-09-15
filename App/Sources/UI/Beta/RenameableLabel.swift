import SwiftUI

/// The editable name under a springboard tile. Owns every rule about what renaming
/// means — commit on Return or blur, revert on Escape or empty — so conversation
/// tiles and folder tiles cannot drift apart on the behavior.
struct RenameableLabel: View {
    /// What the label shows when idle, e.g. "#tasks" or "9:42 PM".
    let text: String
    /// What the field starts with when editing begins, e.g. the bare tag "tasks".
    let editSeed: String
    let font: Font
    let color: Color
    /// Set when a tile was just created with a fallback name and wants focus.
    let beginsEditing: Bool
    let onCommit: (String) -> Void
    let onEditingEnded: () -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .multilineTextAlignment(.center)
                    .focused($fieldFocused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
                    .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.12)))
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
                    .help("Click to rename")
                    .accessibilityHint("Double-tap to rename")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: 118)
        .onAppear { if beginsEditing { beginEditing() } }
        .onChange(of: beginsEditing) { _, begins in if begins { beginEditing() } }
    }

    private func beginEditing() {
        draft = editSeed
        editing = true
        fieldFocused = true
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        onEditingEnded()
        // Clear before any re-entry: dismissing the field flips fieldFocused, which
        // fires commit() a second time. An empty draft makes that pass a no-op, the
        // same way cancel() defends itself.
        draft = ""
        guard !value.isEmpty, value != editSeed else { return }   // empty or unchanged reverts
        onCommit(value)
    }

    /// Clearing the draft first makes the commit triggered by losing focus a no-op.
    private func cancel() {
        draft = ""
        editing = false
        onEditingEnded()
    }
}
