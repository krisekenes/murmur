import XCTest
@testable import MurmurCore

final class ScratchpadStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("scratch-\(UUID()).txt")
    }

    func test_saveReloadsAcrossInstances() {
        let url = tempURL()
        let store = ScratchpadStore(fileURL: url)
        XCTAssertEqual(store.text, "")
        store.save("hello\nworld")
        XCTAssertEqual(ScratchpadStore(fileURL: url).text, "hello\nworld")
    }

    func test_clearEmptiesAndPersists() {
        let url = tempURL()
        let store = ScratchpadStore(fileURL: url)
        store.save("something")
        store.clear()
        XCTAssertEqual(store.text, "")
        XCTAssertEqual(ScratchpadStore(fileURL: url).text, "")
    }
}
