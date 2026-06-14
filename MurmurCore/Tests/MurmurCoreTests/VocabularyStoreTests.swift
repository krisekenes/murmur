import XCTest
@testable import MurmurCore

final class VocabularyStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vocab-\(UUID()).json")
    }

    func test_addPersistsAndDeduplicatesCaseInsensitively() throws {
        let url = tempURL()
        let store = try VocabularyStore(fileURL: url)
        store.add("Kristoffer")
        store.add("kristoffer")
        store.add("Mossflower")
        XCTAssertEqual(store.words, ["Kristoffer", "Mossflower"])

        let reloaded = try VocabularyStore(fileURL: url)
        XCTAssertEqual(reloaded.words, ["Kristoffer", "Mossflower"])
    }

    func test_removeDeletesAndPersists() throws {
        let url = tempURL()
        let store = try VocabularyStore(fileURL: url)
        store.add("Alpha"); store.add("Beta")
        store.remove("Alpha")
        XCTAssertEqual(store.words, ["Beta"])
        XCTAssertEqual(try VocabularyStore(fileURL: url).words, ["Beta"])
    }

    func test_blankInputIsIgnored() throws {
        let store = try VocabularyStore(fileURL: tempURL())
        store.add("   ")
        XCTAssertTrue(store.words.isEmpty)
    }
}
