import SwiftUI

/// Murmur's primary window: a sidebar split of the dictation feed (left) and the
/// editable scratchpad (right), with a top bar carrying search and live status.
struct MainWindowView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.5)
            HSplitView {
                FeedView(state: state, search: $search)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 440)
                ScratchpadView(state: state)
                    .frame(minWidth: 380)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Murmur").font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("Search dictations", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(maxWidth: 220)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.07)))

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
