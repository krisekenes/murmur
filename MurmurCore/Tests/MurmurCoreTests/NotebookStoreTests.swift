import XCTest
@testable import MurmurCore

final class NotebookStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("notebook-\(UUID()).json")
    }

    func test_preservesCorruptNotebookBeforeReplacingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notebook.json")
        let original = Data("broken notebook".utf8)
        try original.write(to: url)
        let store = NotebookStore(fileURL: url)
        store.updateCurrent(content: "new note")
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "corrupt" })
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(NotebookStore(fileURL: url).currentContent, "new note")
    }

    func test_oldNotebookLoadsWithoutMetadata() throws {
        let url = tempURL()
        let id = UUID()
        let json = "{\"pages\":[{\"id\":\"\(id.uuidString)\",\"content\":\"Old note\",\"updatedAt\":0}],\"currentID\":\"\(id.uuidString)\"}"
        try Data(json.utf8).write(to: url)
        let store = NotebookStore(fileURL: url)
        XCTAssertEqual(store.currentContent, "Old note")
        XCTAssertEqual(store.currentID, id)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.pages[0].tags.isEmpty)
        store.addTag(" #My Tag ")
        XCTAssertEqual(NotebookStore(fileURL: url).pages[0].tags, ["my-tag"])
    }

    func test_folderLifecyclePreservesNotesAndTags() throws {
        let url = tempURL()
        let store = NotebookStore(fileURL: url)
        let folder = try XCTUnwrap(store.createFolder(name: " Work "))
        XCTAssertEqual(store.createFolder(name: "work"), folder)
        XCTAssertNil(store.createFolder(name: "  "))
        store.updateCurrent(content: "Keep this note")
        store.moveCurrent(to: folder)
        store.addTag("Meeting")
        store.addTag("#meeting")
        store.addTag("   ")
        let second = store.newPage(folderID: folder)
        store.updateCurrent(content: "Second note")
        XCTAssertTrue(store.renameFolder(folder, name: "Projects"))
        let other = try XCTUnwrap(store.createFolder(name: "Other"))
        XCTAssertFalse(store.renameFolder(other, name: "projects"))
        let reloaded = NotebookStore(fileURL: url)
        XCTAssertEqual(reloaded.currentID, second)
        XCTAssertEqual(reloaded.pages.map(\.folderID), [folder, folder])
        XCTAssertEqual(reloaded.pages[0].tags, ["meeting"])
        reloaded.deleteFolder(folder)
        let final = NotebookStore(fileURL: url)
        XCTAssertEqual(final.pages.map(\.content), ["Keep this note", "Second note"])
        XCTAssertTrue(final.pages.allSatisfy { $0.folderID == nil })
        final.select(final.pages[0].id)
        final.removeTag("meeting")
        final.moveCurrent(to: UUID())
        XCTAssertNil(final.pages[0].folderID)
        XCTAssertTrue(NotebookStore(fileURL: url).pages[0].tags.isEmpty)
    }

    func test_smartTagsUseTopicsHashtagsAndExistingVocabulary() {
        let tags = NoteTagger.suggestions(for: "Meeting agenda for the Apollo launch #Release", existing: ["meetings"], vocabulary: ["apollo-launch"])
        XCTAssertEqual(tags, ["release", "apollo-launch"])
        XCTAssertEqual(NoteTagger.suggestions(for: ""), [])
        XCTAssertEqual(NoteTagger.suggestions(for: "hotel flight itinerary"), ["travel"])
        XCTAssertEqual(NoteTagger.suggestions(for: "decode debugger"), [])
        XCTAssertLessThanOrEqual(NoteTagger.suggestions(for: "meeting todo idea project flight study code journal").count, 5)
    }

    func test_startsWithOnePage() {
        let store = NotebookStore(fileURL: tempURL())
        XCTAssertEqual(store.pages.count, 1)
        XCTAssertEqual(store.currentContent, "")
    }

    func test_migratesLegacyScratchpadIntoFirstPage() throws {
        let legacy = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID()).txt")
        try "my old note".write(to: legacy, atomically: true, encoding: .utf8)
        let store = NotebookStore(fileURL: tempURL(), legacyTextURL: legacy)
        XCTAssertEqual(store.pages.count, 1)
        XCTAssertEqual(store.currentContent, "my old note")
    }

    func test_newPageSwitchesAndPersists() {
        let url = tempURL()
        let store = NotebookStore(fileURL: url)
        store.updateCurrent(content: "page one")
        let newID = store.newPage()
        XCTAssertEqual(store.currentID, newID)
        XCTAssertEqual(store.currentContent, "")
        store.updateCurrent(content: "page two")

        let reloaded = NotebookStore(fileURL: url)
        XCTAssertEqual(reloaded.pages.count, 2)
        XCTAssertEqual(reloaded.currentContent, "page two")
        XCTAssertEqual(reloaded.pages.map(\.content).sorted(), ["page one", "page two"])
    }

    func test_deleteKeepsAtLeastOnePage() {
        let store = NotebookStore(fileURL: tempURL())
        store.updateCurrent(content: "only page")
        store.delete(store.currentID)
        XCTAssertEqual(store.pages.count, 1)          // a fresh blank replaces it
        XCTAssertEqual(store.currentContent, "")
    }

    func test_displayTitleFromFirstNonEmptyLine() {
        let page = ScratchpadPage(content: "\n  Meeting notes  \nrest", updatedAt: Date())
        XCTAssertEqual(page.displayTitle, "Meeting notes")
        XCTAssertEqual(ScratchpadPage(content: "   ", updatedAt: Date()).displayTitle, "Untitled")
    }

    private func anchorStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notebook.json")
    }

    func test_createFolderSeedsAndPersistsAnchors() throws {
        let url = anchorStoreURL()
        let store = NotebookStore(fileURL: url)
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))

        let reloaded = NotebookStore(fileURL: url)
        XCTAssertEqual(reloaded.folders.first { $0.id == id }?.anchorTags, ["interview": 3.0])
    }

    func test_createFolderWithExistingNameMergesAnchorsKeepingTheStronger() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let first = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0, "work": 1.0]))
        let second = try XCTUnwrap(store.createFolder(name: "interviews", anchors: ["interview": 1.0, "tasks": 2.0]))

        XCTAssertEqual(first, second, "a case-insensitive name match must merge, not duplicate")
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders[0].anchorTags, ["interview": 3.0, "work": 1.0, "tasks": 2.0])
    }

    func test_createFolderWithoutAnchorsLeavesExistingAnchorsUntouched() throws {
        let url = anchorStoreURL()
        let store = NotebookStore(fileURL: url)
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))

        // A no-op merge must not rewrite the file. In-memory state looks identical
        // either way, so the modification date is the only signal that catches it.
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        XCTAssertEqual(store.createFolder(name: "Interviews"), id)

        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(store.folders[0].anchorTags, ["interview": 3.0])
        XCTAssertEqual(before, after, "no anchors supplied — createFolder must not rewrite the notebook")
    }

    func test_reinforceAnchorsRaisesWeightsAndPersists() throws {
        let url = anchorStoreURL()
        let store = NotebookStore(fileURL: url)
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        store.reinforceAnchors(id, with: ["interview", "screener"])

        let reloaded = NotebookStore(fileURL: url)
        let anchors = try XCTUnwrap(reloaded.folders.first { $0.id == id }?.anchorTags)
        XCTAssertEqual(anchors["interview"], 4.0)
        XCTAssertEqual(anchors["screener"], 1.0)
    }

    func test_reinforceAnchorsIgnoresAnUnknownFolder() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        store.reinforceAnchors(UUID(), with: ["anything"])
        XCTAssertEqual(store.folders.first { $0.id == id }?.anchorTags, ["interview": 3.0])
    }

    func test_deletingAFolderRemovesItsAnchors() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        store.deleteFolder(id)
        XCTAssertTrue(store.folders.isEmpty)
    }
}
