import Foundation

public struct FolderSuggestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var folderName: String
    public let reason: String

    public init(id: UUID, folderName: String, reason: String) {
        self.id = id
        self.folderName = folderName
        self.reason = reason
    }
}

/// A local, reviewable organizer. Existing folder names and previously filed tags
/// take priority over creating topic folders. Ambiguous existing matches are skipped.
public enum SmartFolderOrganizer {
    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map {
            let word = String($0)
            return word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
        })
    }

    public static func suggestions(entries: [HistoryEntry], folders: [NoteFolder]) -> [FolderSuggestion] {
        return entries.filter { $0.folderID == nil }.compactMap { entry in
            let tags = Set(entry.tags.map(NoteTagger.normalize))
            let contentWords = words(entry.polished + " " + entry.tags.joined(separator: " "))
            let ranked = folders.compactMap { folder -> (NoteFolder, Int, String)? in
                let nameWords = words(folder.name)
                let nameMatch = !nameWords.isEmpty && nameWords.isSubset(of: contentWords)
                let filed = entries.filter { $0.folderID == folder.id }
                let matchingTags = Set(filed.flatMap(\.tags)).intersection(tags)
                let score = (nameMatch ? 10 : 0) + min(matchingTags.count, 5)
                guard score > 0 else { return nil }
                let reason = nameMatch ? "Matches folder name" : "Shares tags with conversations in this folder"
                return (folder, score, reason)
            }.sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
            if let best = ranked.first {
                guard ranked.count == 1 || best.1 > ranked[1].1 else { return nil }
                return FolderSuggestion(id: entry.id, folderName: best.0.name, reason: best.2)
            }
            // Prefer a specific topic over a broad Work tag.
            let raw = entry.tags.first { $0 != "work" } ?? entry.tags.first
            // Normalize once here so the folder name and the reason string can
            // never disagree, and so the lookup does not depend on callers
            // having pre-normalized entry.tags.
            let topic = raw.map(NoteTagger.normalize) ?? ""
            guard !topic.isEmpty else { return nil }
            let name = FolderNaming.displayName(for: topic)
            return FolderSuggestion(id: entry.id, folderName: name, reason: "Tagged #\(topic)")
        }
    }

    /// Recheck live state so a preview never overrides a manual move or revives a deleted entry.
    @discardableResult
    public static func apply(_ suggestions: [FolderSuggestion], history: HistoryStore, notebook: NotebookStore) -> [UUID: UUID] {
        let unfiled = Set(history.entries.filter { $0.folderID == nil }.map(\.id))
        var destinations: [UUID: UUID] = [:]
        for suggestion in suggestions where unfiled.contains(suggestion.id) && destinations[suggestion.id] == nil {
            guard let folderID = notebook.createFolder(name: suggestion.folderName) else { continue }
            destinations[suggestion.id] = folderID
        }
        return history.organizeUnfiled(destinations)
    }
}
