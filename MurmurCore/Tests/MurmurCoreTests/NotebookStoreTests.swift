import XCTest
@testable import MurmurCore

final class NotebookStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("notebook-\(UUID()).json")
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
}
