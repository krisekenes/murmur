import XCTest
@testable import MurmurCore

final class HistoryStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
    }

    private func entry(_ text: String, at t: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), raw: text, polished: text, createdAt: Date(timeIntervalSince1970: t), appName: "TextEdit")
    }

    func test_appendStoresNewestFirstAndPersists() throws {
        let url = tempURL()
        let store = try HistoryStore(fileURL: url, limit: 200)
        store.append(entry("first", at: 1))
        store.append(entry("second", at: 2))
        XCTAssertEqual(store.entries.map(\.raw), ["second", "first"])
        XCTAssertEqual(try HistoryStore(fileURL: url, limit: 200).entries.map(\.raw), ["second", "first"])
    }

    func test_capDropsOldest() throws {
        let store = try HistoryStore(fileURL: tempURL(), limit: 3)
        for i in 1...5 { store.append(entry("e\(i)", at: TimeInterval(i))) }
        XCTAssertEqual(store.entries.map(\.raw), ["e5", "e4", "e3"])
    }

    func test_deleteRemovesById() throws {
        let store = try HistoryStore(fileURL: tempURL(), limit: 200)
        let e = entry("keep", at: 1)
        store.append(entry("drop", at: 2))
        store.append(e)
        store.delete(id: store.entries[0].id)
        XCTAssertEqual(store.entries.map(\.raw), ["drop"])
    }
}
