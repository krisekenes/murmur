import SwiftUI
import MurmurCore

/// The feed pane: a searchable, date-grouped list of past dictations.
struct FeedView: View {
    @ObservedObject var state: AppState
    @Binding var search: String

    private var filtered: [HistoryEntry] {
        guard !search.isEmpty else { return state.historyEntries }
        return state.historyEntries.filter { $0.polished.localizedCaseInsensitiveContains(search) }
    }

    private var groups: [(title: String, entries: [HistoryEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (title: Self.dayTitle(day, calendar: cal), entries: grouped[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if filtered.isEmpty {
                    Text(search.isEmpty ? "No dictations yet" : "No matches")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                            ForEach(group.entries) { entry in
                                FeedCard(
                                    entry: entry,
                                    onCopy: { copy(entry.polished) },
                                    onAppend: { state.appendToScratchpad(entry.polished) },
                                    onDelete: { state.deleteDictation(id: entry.id) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.ultraThinMaterial)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy"
        return f.string(from: day)
    }
}

/// One dictation card in the feed.
struct FeedCard: View {
    let entry: HistoryEntry
    let onCopy: () -> Void
    let onAppend: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.polished)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(entry.createdAt, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                Text(entry.appName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hover {
                    iconButton("arrow.right.to.line", help: "Send to scratchpad", action: onAppend)
                    iconButton("doc.on.doc", help: "Copy", action: onCopy)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hover ? 0.07 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .contextMenu {
            Button("Send to Scratchpad", action: onAppend)
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
