import XCTest
@testable import MurmurCore

final class TileGroupingTests: XCTestCase {

    // MARK: propose

    func test_singleSharedTagNamesTheFolderConfidently() {
        let proposal = TileGrouping.propose(["interview", "work"], ["interview", "tasks"])
        XCTAssertEqual(proposal.suggestedName, "Interviews")
        XCTAssertTrue(proposal.isConfident)
        XCTAssertEqual(proposal.anchors["interview"], TileGrouping.sharedWeight)
        XCTAssertEqual(proposal.anchors["work"], TileGrouping.coOccurringWeight)
        XCTAssertEqual(proposal.anchors["tasks"], TileGrouping.coOccurringWeight)
    }

    func test_multipleSharedTagsTieBreakDeterministically() {
        let proposal = TileGrouping.propose(["work", "ideas"], ["work", "ideas"])
        // Both shared; "work" sits earlier in both lists, so it wins the name.
        XCTAssertEqual(proposal.suggestedName, "Work")
        XCTAssertEqual(proposal.anchors["work"], TileGrouping.sharedWeight)
        XCTAssertEqual(proposal.anchors["ideas"], TileGrouping.sharedWeight)
    }

    func test_proposeIsOrderIndependentForTheSameInputs() {
        let forward = TileGrouping.propose(["work", "ideas"], ["ideas", "work"])
        let backward = TileGrouping.propose(["ideas", "work"], ["work", "ideas"])
        XCTAssertEqual(forward.suggestedName, backward.suggestedName)
        XCTAssertEqual(forward.anchors, backward.anchors)
    }

    func test_noSharedTagsFallsBackToNewFolderWithoutConfidence() {
        let proposal = TileGrouping.propose(["travel"], ["engineering"])
        XCTAssertEqual(proposal.suggestedName, TileGrouping.defaultFolderName)
        XCTAssertFalse(proposal.isConfident)
        XCTAssertEqual(proposal.anchors["travel"], TileGrouping.coOccurringWeight)
        XCTAssertEqual(proposal.anchors["engineering"], TileGrouping.coOccurringWeight)
    }

    func test_bothUntaggedProducesNoAnchors() {
        let proposal = TileGrouping.propose([], [])
        XCTAssertEqual(proposal.suggestedName, TileGrouping.defaultFolderName)
        XCTAssertFalse(proposal.isConfident)
        XCTAssertEqual(proposal.anchors, [:])
    }

    func test_proposeNormalizesTags() {
        let proposal = TileGrouping.propose(["#Job Interview"], ["Job  Interview"])
        XCTAssertEqual(proposal.suggestedName, "Job Interview")
        XCTAssertEqual(proposal.anchors, ["job-interview": TileGrouping.sharedWeight])
    }

    // MARK: naming

    func test_displayNameMatchesSmartOrganizerTopicNames() {
        XCTAssertEqual(FolderNaming.displayName(for: "interview"), "Interviews")
        XCTAssertEqual(FolderNaming.displayName(for: "engineering"), "Engineering")
        XCTAssertEqual(FolderNaming.displayName(for: "machine-learning"), "Machine Learning")
    }

    // MARK: reinforcement

    func test_reinforcementRaisesWeightAndNormalizes() {
        let result = TileGrouping.reinforced([:], with: ["#Job Interview"])
        XCTAssertEqual(result, ["job-interview": TileGrouping.coOccurringWeight])
    }

    func test_reinforcementIsMonotonicAndBounded() {
        var anchors: [String: Double] = [:]
        var previous = 0.0
        for _ in 0..<50 {
            anchors = TileGrouping.reinforced(anchors, with: ["interview"])
            let current = try! XCTUnwrap(anchors["interview"])
            XCTAssertGreaterThanOrEqual(current, previous, "weights must never decrease")
            XCTAssertLessThanOrEqual(current, TileGrouping.maxWeight, "weights must stay bounded")
            previous = current
        }
        XCTAssertEqual(previous, TileGrouping.maxWeight)
    }

    func test_reinforcementLeavesUnrelatedAnchorsAlone() {
        let result = TileGrouping.reinforced(["work": 2.0], with: ["interview"])
        XCTAssertEqual(result["work"], 2.0)
        XCTAssertEqual(result["interview"], TileGrouping.coOccurringWeight)
    }

    func test_reinforcementIgnoresBlankTags() {
        XCTAssertEqual(TileGrouping.reinforced([:], with: ["  ", "#"]), [:])
    }

    // MARK: merging

    func test_mergeKeepsTheStrongerWeightForEachTag() {
        let merged = TileGrouping.merged(["interview": 3.0, "work": 1.0],
                                         ["interview": 1.0, "tasks": 2.0])
        XCTAssertEqual(merged, ["interview": 3.0, "work": 1.0, "tasks": 2.0])
    }

    // MARK: SmartFolderOrganizer naming/reason agreement

    func test_suggestionNameAndReasonAgreeForANonNormalizedTag() {
        let entry = HistoryEntry(id: UUID(), raw: "r", polished: "p",
                                 createdAt: Date(), appName: "Murmur", tags: ["Interview"])
        let suggestions = SmartFolderOrganizer.suggestions(entries: [entry], folders: [])
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].folderName, "Interviews")
        XCTAssertEqual(suggestions[0].reason, "Tagged #interview")
    }
}
