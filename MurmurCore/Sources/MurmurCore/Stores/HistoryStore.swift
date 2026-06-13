import Foundation

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let raw: String
    public let polished: String
    public let createdAt: Date
    public let appName: String

    public init(id: UUID, raw: String, polished: String, createdAt: Date, appName: String) {
        self.id = id; self.raw = raw; self.polished = polished
        self.createdAt = createdAt; self.appName = appName
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
