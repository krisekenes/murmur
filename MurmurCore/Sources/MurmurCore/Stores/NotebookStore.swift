import Foundation

/// One scratchpad page. Its title is derived from the first non-empty line.
public struct ScratchpadPage: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var content: String
    public var updatedAt: Date
    public var folderID: UUID?
    public var tags: [String]

    public init(id: UUID = UUID(), content: String = "", updatedAt: Date, folderID: UUID? = nil, tags: [String] = []) {
        self.id = id
        self.content = content
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey { case id, content, updatedAt, folderID, tags }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        content = try values.decode(String.self, forKey: .content)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// Title from the first non-empty line (the note's "name"), else "Untitled".
    public var displayTitle: String {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(40)) }
        }
        return "Untitled"
    }
}

public struct NoteFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
}

/// A notebook of scratchpad pages with a current selection, persisted as JSON.
/// Migrates a legacy single scratchpad.txt into the first page on first run.
public final class NotebookStore {
    private struct Notebook: Codable { var pages: [ScratchpadPage]; var currentID: UUID; var folders: [NoteFolder]? }

    public private(set) var pages: [ScratchpadPage]
    public private(set) var currentID: UUID
    public private(set) var folders: [NoteFolder] = []
    private let fileURL: URL
    private var persistenceBlocked = false

    public init(fileURL: URL, legacyTextURL: URL? = nil, now: Date = Date()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let nb = try? JSONDecoder().decode(Notebook.self, from: data),
           !nb.pages.isEmpty {
            folders = nb.folders ?? []
            pages = nb.pages
            currentID = nb.pages.contains(where: { $0.id == nb.currentID }) ? nb.currentID : nb.pages[0].id
        } else {
            // Preserve unreadable notebooks before creating a replacement.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = fileURL.appendingPathExtension("\(UUID().uuidString).corrupt")
                do { try FileManager.default.copyItem(at: fileURL, to: backup) }
                catch {
                    let page = ScratchpadPage(content: "", updatedAt: now)
                    pages = [page]
                    currentID = page.id
                    persistenceBlocked = true
                    return
                }
            }
            let legacy = legacyTextURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            let page = ScratchpadPage(content: legacy, updatedAt: now)
            pages = [page]
            currentID = page.id
            persist()
        }
    }

    public var currentContent: String {
        pages.first(where: { $0.id == currentID })?.content ?? ""
    }

    public func updateCurrent(content: String, now: Date = Date()) {
        guard let idx = pages.firstIndex(where: { $0.id == currentID }) else { return }
        pages[idx].content = content
        pages[idx].updatedAt = now
        persist()
    }

    @discardableResult
    public func newPage(now: Date = Date(), folderID: UUID? = nil) -> UUID {
        var page = ScratchpadPage(content: "", updatedAt: now)
        page.folderID = folders.contains { $0.id == folderID } ? folderID : nil
        pages.append(page)
        currentID = page.id
        persist()
        return page.id
    }

    public func select(_ id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        currentID = id
        persist()
    }

    /// Deletes a page, always leaving at least one (a fresh blank if the last is removed).
    public func delete(_ id: UUID, now: Date = Date()) {
        pages.removeAll { $0.id == id }
        if pages.isEmpty {
            let page = ScratchpadPage(content: "", updatedAt: now)
            pages = [page]
            currentID = page.id
        } else if currentID == id {
            currentID = pages[0].id
        }
        persist()
    }

    @discardableResult
    public func createFolder(name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = folders.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }
        let folder = NoteFolder(id: UUID(), name: name)
        folders.append(folder)
        persist()
        return folder.id
    }

    @discardableResult
    public func renameFolder(_ id: UUID, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = folders.firstIndex(where: { $0.id == id }),
              !folders.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        folders[index].name = name
        persist()
        return true
    }

    /// Removing a folder keeps its notes in Unfiled.
    public func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for index in pages.indices where pages[index].folderID == id { pages[index].folderID = nil }
        persist()
    }

    public func moveCurrent(to folderID: UUID?) {
        guard folderID == nil || folders.contains(where: { $0.id == folderID }),
              let index = pages.firstIndex(where: { $0.id == currentID }) else { return }
        pages[index].folderID = folderID
        persist()
    }

    public func addTag(_ tag: String) {
        let tag = NoteTagger.normalize(tag)
        guard !tag.isEmpty, let index = pages.firstIndex(where: { $0.id == currentID }),
              !pages[index].tags.contains(tag) else { return }
        pages[index].tags.append(tag)
        persist()
    }

    public func removeTag(_ tag: String) {
        guard let index = pages.firstIndex(where: { $0.id == currentID }) else { return }
        pages[index].tags.removeAll { $0 == tag }
        persist()
    }

    private func persist() {
        guard !persistenceBlocked, let data = try? JSONEncoder().encode(Notebook(pages: pages, currentID: currentID, folders: folders)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
