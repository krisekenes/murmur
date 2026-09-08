import Foundation

/// One scratchpad page. Its title is derived from the first non-empty line.
public struct ScratchpadPage: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var content: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), content: String = "", updatedAt: Date) {
        self.id = id
        self.content = content
        self.updatedAt = updatedAt
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

/// A notebook of scratchpad pages with a current selection, persisted as JSON.
/// Migrates a legacy single scratchpad.txt into the first page on first run.
public final class NotebookStore {
    private struct Notebook: Codable { var pages: [ScratchpadPage]; var currentID: UUID }

    public private(set) var pages: [ScratchpadPage]
    public private(set) var currentID: UUID
    private let fileURL: URL
    private var persistenceBlocked = false

    public init(fileURL: URL, legacyTextURL: URL? = nil, now: Date = Date()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let nb = try? JSONDecoder().decode(Notebook.self, from: data),
           !nb.pages.isEmpty {
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
    public func newPage(now: Date = Date()) -> UUID {
        let page = ScratchpadPage(content: "", updatedAt: now)
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

    private func persist() {
        guard !persistenceBlocked, let data = try? JSONEncoder().encode(Notebook(pages: pages, currentID: currentID)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
