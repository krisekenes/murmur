import XCTest
@testable import MurmurCore

final class FolderNamePromptBuilderTests: XCTestCase {

    private let builder = FolderNamePromptBuilder()

    // MARK: sanitize

    func test_acceptsABareNameAndTitleCasesIt() {
        XCTAssertEqual(builder.sanitize("roadmap"), "Roadmap")
        XCTAssertEqual(builder.sanitize("lease renewal"), "Lease Renewal")
    }

    func test_stripsTheQuotesAndTrailingStopsSmallModelsAdd() {
        XCTAssertEqual(builder.sanitize("\"Roadmap\""), "Roadmap")
        XCTAssertEqual(builder.sanitize("  Roadmap.  "), "Roadmap")
        XCTAssertEqual(builder.sanitize("**Roadmap**"), "Roadmap")
    }

    func test_stripsAShortLeadingLabel() {
        XCTAssertEqual(builder.sanitize("Folder name: Roadmap"), "Roadmap")
    }

    func test_rejectsAnswersThatIgnoredTheInstruction() {
        // A sentence, an explanation, or markdown is unusable — the caller keeps
        // its placeholder rather than writing junk into the notebook.
        XCTAssertNil(builder.sanitize("Sure! Here is a good folder name for you"))
        XCTAssertNil(builder.sanitize("Roadmap\nInterviews"))
        XCTAssertNil(builder.sanitize(""))
        XCTAssertNil(builder.sanitize("   "))
    }

    func test_rejectsTheePlaceholderItWasToldToReplace() {
        XCTAssertNil(builder.sanitize(TileGrouping.defaultFolderName))
        XCTAssertNil(builder.sanitize("new folder"))
    }

    func test_honoursTheWordCeiling() {
        let tight = FolderNamePromptBuilder(maxWords: 2)
        XCTAssertEqual(tight.sanitize("Lease Renewal"), "Lease Renewal")
        XCTAssertNil(tight.sanitize("Lease Renewal Paperwork"))
    }

    // MARK: excerpt

    func test_shortTranscriptsPassThroughUntouched() {
        XCTAssertEqual(builder.excerpt("  the roadmap slipped  "), "the roadmap slipped")
    }

    func test_longTranscriptsCutOnAWordBoundary() {
        let builder = FolderNamePromptBuilder(excerptLength: 10)
        // "the roadmap" is 11 characters, so the cut lands mid-word and must
        // retreat to the last space rather than emit "the roadma".
        XCTAssertEqual(builder.excerpt("the roadmap slipped again"), "the")
    }

    func test_userPromptLabelsBothConversations() {
        let prompt = builder.userPrompt("first one", "second one")
        XCTAssertTrue(prompt.contains("Conversation A:"))
        XCTAssertTrue(prompt.contains("Conversation B:"))
        XCTAssertTrue(prompt.contains("first one"))
        XCTAssertTrue(prompt.contains("second one"))
    }

    // MARK: systemPrompt

    func test_systemPromptNamesThePlaceholderItMustNotEmit() {
        // The rule and the sanitizer have to agree on the forbidden string, or
        // the model is told one thing and judged by another.
        XCTAssertTrue(builder.systemPrompt().contains(TileGrouping.defaultFolderName))
    }
}
