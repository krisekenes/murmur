import SwiftUI
import MurmurCore

public struct HistoryView: View {
    @ObservedObject var state: AppState
    @State private var query = ""

    public init(state: AppState) { self.state = state }

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return state.historyEntries }
        return state.historyEntries.filter { $0.polished.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Search dictations", text: $query)
                .textFieldStyle(.roundedBorder).padding(8)
            Divider()
            List {
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.polished).font(.system(size: 13))
                        HStack {
                            Text(entry.createdAt, style: .relative).font(.system(size: 11, design: .monospaced))
                            Text(entry.appName).font(.system(size: 11))
                        }.foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.polished, forType: .string)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { state.deleteDictation(id: entry.id) } }
                }
            }
        }
        .frame(width: 380, height: 480)
    }
}
