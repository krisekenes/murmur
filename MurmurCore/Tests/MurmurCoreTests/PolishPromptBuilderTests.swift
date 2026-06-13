import XCTest
@testable import MurmurCore

final class PolishPromptBuilderTests: XCTestCase {
    func test_shouldPolish_respectsWordThreshold() {
        let b = PolishPromptBuilder(minWords: 4)
        XCTAssertFalse(b.shouldPolish("yes"))
        XCTAssertFalse(b.shouldPolish("send it now"))      // 3 words
        XCTAssertTrue(b.shouldPolish("send it to her now")) // 5 words
    }

    func test_systemPrompt_includesVocabularyWhenPresent() {
        let b = PolishPromptBuilder(minWords: 4)
        let prompt = b.systemPrompt(vocabulary: ["Kristoffer", "Mossflower"])
        XCTAssertTrue(prompt.contains("Kristoffer"))
        XCTAssertTrue(prompt.contains("Mossflower"))
    }

    func test_systemPrompt_omitsVocabularySectionWhenEmpty() {
        let b = PolishPromptBuilder(minWords: 4)
        let prompt = b.systemPrompt(vocabulary: [])
        XCTAssertFalse(prompt.lowercased().contains("preferred spellings"))
    }
}
