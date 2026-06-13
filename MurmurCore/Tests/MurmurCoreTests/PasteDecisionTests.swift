import XCTest
@testable import MurmurCore

final class PasteDecisionTests: XCTestCase {
    func test_restoresWhenWeStillOwnPasteboard() {
        let d = PasteDecision(ownedChangeCount: 42)
        XCTAssertTrue(d.shouldRestore(currentChangeCount: 42))
    }

    func test_skipsRestoreWhenSomeoneElseCopied() {
        let d = PasteDecision(ownedChangeCount: 42)
        XCTAssertFalse(d.shouldRestore(currentChangeCount: 43))
    }
}
