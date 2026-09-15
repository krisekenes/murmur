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

    func test_oldConversationsReceiveTagsAndRemovalSurvivesReload() throws {
        let url = tempURL()
        let id = UUID()
        let legacy: [[String: Any]] = [["id": id.uuidString, "raw": "Interview preparation", "polished": "Interview preparation", "createdAt": 0, "appName": "Murmur"]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let store = try HistoryStore(fileURL: url)
        XCTAssertEqual(store.entries[0].tags, ["interview"])
        XCTAssertEqual(store.entries[0].id, id)
        store.removeTag("interview", from: id)
        XCTAssertEqual(try HistoryStore(fileURL: url).entries[0].tags, [])
        XCTAssertEqual(try HistoryStore(fileURL: url).entries[0].polished, "Interview preparation")
    }

    func test_conversationOrganizationPersistsAndUnfilingKeepsContent() throws {
        let url = tempURL()
        let store = try HistoryStore(fileURL: url)
        let conversation = entry("Meeting agenda", at: 1)
        XCTAssertEqual(conversation.tags, ["meetings"])
        store.append(conversation)
        store.addTag(" #My Project ", to: conversation.id)
        store.addTag("my-project", to: conversation.id)
        let folder = UUID()
        store.move(conversation.id, to: folder)
        let reloaded = try HistoryStore(fileURL: url)
        XCTAssertEqual(reloaded.entries[0].tags, ["meetings", "my-project"])
        XCTAssertEqual(reloaded.entries[0].folderID, folder)
        reloaded.unfile(folderID: folder)
        let unfiled = try HistoryStore(fileURL: url)
        XCTAssertNil(unfiled.entries[0].folderID)
        XCTAssertEqual(unfiled.entries[0].raw, "Meeting agenda")
        XCTAssertEqual(unfiled.entries[0].tags, ["meetings", "my-project"])
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
