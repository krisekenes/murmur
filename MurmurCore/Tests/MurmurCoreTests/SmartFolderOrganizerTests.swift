import XCTest
@testable import MurmurCore

final class SmartFolderOrganizerTests: XCTestCase {
    private func entry(_ text: String, tags: [String]? = nil, folderID: UUID? = nil) -> HistoryEntry {
        HistoryEntry(id: UUID(), raw: text, polished: text, createdAt: Date(), appName: "Murmur", tags: tags, folderID: folderID)
    }

    private func stores() throws -> (HistoryStore, NotebookStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (try HistoryStore(fileURL: directory.appendingPathComponent("history.json")),
                NotebookStore(fileURL: directory.appendingPathComponent("notebook.json")), directory)
    }

    func test_existingFolderNameWinsAndFiledConversationsAreSkipped() throws {
        let (_, notebook, _) = try stores()
        let id = try XCTUnwrap(notebook.createFolder(name: "Interviews"))
        let unfiled = entry("Practice for my interview")
        let filed = entry("Another interview", folderID: id)
        let suggestions = SmartFolderOrganizer.suggestions(entries: [unfiled, filed], folders: notebook.folders)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].id, unfiled.id)
        XCTAssertEqual(suggestions[0].folderName, "Interviews")
        XCTAssertEqual(suggestions[0].reason, "Matches folder name")
    }

    func test_usesPreviousFilingAndSkipsAmbiguousMatches() throws {
        let (_, notebook, _) = try stores()
        let career = try XCTUnwrap(notebook.createFolder(name: "Career"))
        let other = try XCTUnwrap(notebook.createFolder(name: "Other"))
        let unfiled = entry("Interview tomorrow")
        let filed = entry("Interview yesterday", folderID: career)
        let suggestions = SmartFolderOrganizer.suggestions(entries: [unfiled, filed], folders: notebook.folders)
        XCTAssertEqual(suggestions.map(\.folderName), ["Career"])
        let ambiguous = SmartFolderOrganizer.suggestions(entries: [unfiled, filed, entry("Interview notes", folderID: other)], folders: notebook.folders)
        XCTAssertTrue(ambiguous.isEmpty)
    }

    func test_suggestsSpecificTopicAndLeavesUnrecognizedTextAlone() {
        let suggestions = SmartFolderOrganizer.suggestions(entries: [entry("Hello"), entry("My project interview", tags: ["work", "interview"])], folders: [])
        XCTAssertEqual(suggestions.map(\.folderName), ["Interviews"])
    }

    func test_applyRechecksStateDeduplicatesFoldersAndUndoPreservesLaterMoves() throws {
        let (history, notebook, directory) = try stores()
        let first = entry("Interview one")
        let second = entry("Interview two")
        let deleted = entry("Travel itinerary")
        let manual = entry("Meeting agenda")
        for conversation in [first, second, deleted, manual] { history.append(conversation) }
        let preview = SmartFolderOrganizer.suggestions(entries: history.entries, folders: notebook.folders)
        XCTAssertTrue(notebook.folders.isEmpty) // A preview has no side effects.
        history.delete(id: deleted.id)
        let manualFolder = try XCTUnwrap(notebook.createFolder(name: "Mine"))
        history.move(manual.id, to: manualFolder)
        let moves = SmartFolderOrganizer.apply(preview, history: history, notebook: notebook)
        XCTAssertEqual(moves.count, 2)
        XCTAssertEqual(Set(notebook.folders.map(\.name)), ["Mine", "Interviews"])
        XCTAssertEqual(moves[first.id], moves[second.id])
        let reloaded = try HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        XCTAssertEqual(reloaded.entries.first { $0.id == first.id }?.folderID, moves[first.id])
        reloaded.move(second.id, to: manualFolder)
        reloaded.undoOrganization(moves)
        XCTAssertNil(reloaded.entries.first { $0.id == first.id }?.folderID)
        XCTAssertEqual(reloaded.entries.first { $0.id == second.id }?.folderID, manualFolder)
        XCTAssertEqual(reloaded.entries.first { $0.id == manual.id }?.folderID, manualFolder)
        XCTAssertEqual(reloaded.entries.count, 3)
        XCTAssertEqual(try HistoryStore(fileURL: directory.appendingPathComponent("history.json")).entries, reloaded.entries)
    }

    func test_editedDestinationReusesFolderAndBlankDestinationIsIgnored() throws {
        let (history, notebook, _) = try stores()
        let conversation = entry("Interview")
        history.append(conversation)
        let career = try XCTUnwrap(notebook.createFolder(name: "Career"))
        let ignored = SmartFolderOrganizer.apply([FolderSuggestion(id: conversation.id, folderName: "  ", reason: "")], history: history, notebook: notebook)
        XCTAssertTrue(ignored.isEmpty)
        let moves = SmartFolderOrganizer.apply([FolderSuggestion(id: conversation.id, folderName: " career ", reason: "")], history: history, notebook: notebook)
        XCTAssertEqual(moves[conversation.id], career)
        XCTAssertEqual(notebook.folders.count, 1)
    }

    func test_anchorWeightOutranksAFolderNameMatch() throws {
        let (_, notebook, _) = try stores()
        // "Screeners" does not appear in the text, so only its anchor can match it.
        _ = notebook.createFolder(name: "Screeners", anchors: ["interview": TileGrouping.sharedWeight])
        _ = notebook.createFolder(name: "Recruiting")
        let unfiled = entry("notes about recruiting", tags: ["interview"])

        let suggestions = SmartFolderOrganizer.suggestions(entries: [unfiled], folders: notebook.folders)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].folderName, "Screeners")
        XCTAssertTrue(suggestions[0].reason.contains("interview"), "reason should name the anchor")
    }

    func test_foldersWithoutAnchorsBehaveExactlyAsBefore() throws {
        let (_, notebook, _) = try stores()
        _ = notebook.createFolder(name: "Recruiting")
        let unfiled = entry("notes about recruiting", tags: ["interview"])

        let suggestions = SmartFolderOrganizer.suggestions(entries: [unfiled], folders: notebook.folders)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].folderName, "Recruiting")
        XCTAssertEqual(suggestions[0].reason, "Matches folder name")
    }

    func test_equallyAnchoredFoldersStayUnfiled() throws {
        let (_, notebook, _) = try stores()
        _ = notebook.createFolder(name: "Screeners", anchors: ["interview": TileGrouping.sharedWeight])
        _ = notebook.createFolder(name: "Panels", anchors: ["interview": TileGrouping.sharedWeight])
        let unfiled = entry("some notes", tags: ["interview"])

        let suggestions = SmartFolderOrganizer.suggestions(entries: [unfiled], folders: notebook.folders)

        XCTAssertTrue(suggestions.isEmpty, "an ambiguous anchor match must stay unfiled")
    }

    func test_incidentalCoOccurrenceDoesNotOutrankANameMatch() throws {
        let (_, notebook, _) = try stores()
        _ = notebook.createFolder(name: "Screeners", anchors: ["interview": TileGrouping.coOccurringWeight])
        _ = notebook.createFolder(name: "Recruiting")
        let unfiled = entry("notes about recruiting", tags: ["interview"])

        let suggestions = SmartFolderOrganizer.suggestions(entries: [unfiled], folders: notebook.folders)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].folderName, "Recruiting")
    }
}
