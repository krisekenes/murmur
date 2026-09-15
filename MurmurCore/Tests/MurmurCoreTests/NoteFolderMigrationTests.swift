import XCTest
@testable import MurmurCore

final class NoteFolderMigrationTests: XCTestCase {
    private func freshNotebookURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notebook.json")
    }

    private func setAsideFiles(besides url: URL) throws -> [String] {
        let directory = url.deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return names.filter { $0.hasSuffix(".corrupt") }
    }

    /// A v0.2.0 notebook has no anchorTags key. If decoding it throws, NotebookStore
    /// sets the file aside and replaces it with a single blank page — destroying the
    /// user's pages and folders. This test is the guard against that.
    func test_legacyNotebookWithoutAnchorTagsLoadsIntact() throws {
        let url = freshNotebookURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pageID = UUID()
        let folderID = UUID()
        let legacy = """
        {"pages":[{"id":"\(pageID.uuidString)","content":"keep me","updatedAt":760000000,\
        "folderID":"\(folderID.uuidString)","tags":["work"]}],\
        "currentID":"\(pageID.uuidString)",\
        "folders":[{"id":"\(folderID.uuidString)","name":"Interviews"}]}
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let store = NotebookStore(fileURL: url)

        XCTAssertEqual(store.pages.count, 1)
        XCTAssertEqual(store.pages[0].content, "keep me")
        XCTAssertEqual(store.pages[0].tags, ["work"])
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders[0].id, folderID)
        XCTAssertEqual(store.folders[0].name, "Interviews")
        XCTAssertEqual(store.folders[0].anchorTags, [:])
        XCTAssertEqual(try setAsideFiles(besides: url), [], "notebook must not be treated as corrupt")
    }

    func test_folderWithAnchorsRoundTripsThroughCodable() throws {
        let folder = NoteFolder(id: UUID(), name: "Interviews", anchorTags: ["interview": 3.0])
        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(NoteFolder.self, from: data)
        XCTAssertEqual(decoded, folder)
        XCTAssertEqual(decoded.anchorTags, ["interview": 3.0])
    }

    func test_folderDefaultsToNoAnchors() {
        XCTAssertEqual(NoteFolder(id: UUID(), name: "Work").anchorTags, [:])
    }
}
