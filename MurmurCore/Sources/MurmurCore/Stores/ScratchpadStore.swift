import Foundation

/// Persists the scratchpad's plain text to disk. Mirrors the simple, atomic-write
/// pattern of `HistoryStore`/`VocabularyStore`. Plain text only.
public final class ScratchpadStore {
    public private(set) var text: String = ""
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let loaded = String(data: data, encoding: .utf8) {
            text = loaded
        }
    }

    public func save(_ newText: String) {
        text = newText
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(newText.utf8).write(to: fileURL, options: .atomic)
    }

    public func clear() { save("") }
}
