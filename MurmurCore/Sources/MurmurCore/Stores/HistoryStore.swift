import Foundation

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let raw: String
    public let polished: String
    public let createdAt: Date
    public let appName: String
    public var tags: [String]
    public var folderID: UUID?

    public init(id: UUID, raw: String, polished: String, createdAt: Date, appName: String, tags: [String]? = nil, folderID: UUID? = nil) {
        self.id = id; self.raw = raw; self.polished = polished
        self.createdAt = createdAt; self.appName = appName
        self.tags = tags ?? NoteTagger.suggestions(for: polished)
        self.folderID = folderID
    }

    private enum CodingKeys: String, CodingKey { case id, raw, polished, createdAt, appName, tags, folderID }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        raw = try values.decode(String.self, forKey: .raw)
        polished = try values.decode(String.self, forKey: .polished)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        appName = try values.decode(String.self, forKey: .appName)
        // Old conversations receive tags once; an explicitly emptied list stays empty.
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? NoteTagger.suggestions(for: polished)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
    }

}

public final class HistoryStore {
    public private(set) var entries: [HistoryEntry] = []   // newest first
    private let fileURL: URL
    private let limit: Int

    public init(fileURL: URL, limit: Int = 200) throws {
        self.fileURL = fileURL
        self.limit = limit
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
                entries = decoded
                // Save inferred metadata so future launches keep the same tags.
                persist()
            } else {
                // Don't silently overwrite a corrupt file — set it aside so data can be recovered.
                try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
            }
        }
    }

    public func append(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        persist()
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func addTag(_ tag: String, to id: UUID) {
        let tag = NoteTagger.normalize(tag)
        guard !tag.isEmpty, let index = entries.firstIndex(where: { $0.id == id }),
              !entries[index].tags.contains(tag) else { return }
        entries[index].tags.append(tag)
        persist()
    }

    public func removeTag(_ tag: String, from id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].tags.removeAll { $0 == tag }
        persist()
    }

    /// Promote a tag to index 0 — the springboard shows `tags.first` as the
    /// conversation's filename. Reordering avoids a new stored property, so
    /// search, filters, and the tag editor keep working unchanged.
    public func setPrimaryTag(_ tag: String, for id: UUID) {
        let tag = NoteTagger.normalize(tag)
        guard !tag.isEmpty, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].tags.first != tag else { return }
        entries[index].tags.removeAll { $0 == tag }
        entries[index].tags.insert(tag, at: 0)
        persist()
    }

    public func move(_ id: UUID, to folderID: UUID?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].folderID = folderID
        persist()
    }

    public func unfile(folderID: UUID) {
        for index in entries.indices where entries[index].folderID == folderID { entries[index].folderID = nil }
        persist()
    }

    /// Batch changes in one write and return only moves actually applied.
    @discardableResult
    public func organizeUnfiled(_ destinations: [UUID: UUID]) -> [UUID: UUID] {
        var applied: [UUID: UUID] = [:]
        for index in entries.indices where entries[index].folderID == nil {
            guard let folder = destinations[entries[index].id] else { continue }
            entries[index].folderID = folder
            applied[entries[index].id] = folder
        }
        if !applied.isEmpty { persist() }
        return applied
    }

    /// Undo only entries still in the assigned folder; preserve subsequent manual moves.
    public func undoOrganization(_ moves: [UUID: UUID]) {
        for index in entries.indices {
            guard let folder = moves[entries[index].id], entries[index].folderID == folder else { continue }
            entries[index].folderID = nil
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
