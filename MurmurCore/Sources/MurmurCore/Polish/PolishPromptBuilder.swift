import Foundation

public struct PolishPromptBuilder: Sendable {
    public let minWords: Int
    public init(minWords: Int) { self.minWords = minWords }

    public func wordCount(_ text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    public func shouldPolish(_ text: String) -> Bool {
        wordCount(text) >= minWords
    }

    public func systemPrompt(vocabulary: [String]) -> String {
        var prompt = """
        You clean up dictated speech-to-text. Apply these rules and output ONLY the cleaned text, nothing else:
        - Remove filler words (um, uh, like, you know) and false starts.
        - When the speaker corrects themselves, keep only the corrected version. \
        Example: "send it Tuesday, no, Wednesday" becomes "send it Wednesday".
        - Fix capitalization and punctuation. Do not add content or change meaning.
        - Preserve the speaker's wording and tone otherwise. Do not summarize.
        """
        if !vocabulary.isEmpty {
            prompt += "\n- Use these preferred spellings for names and terms when they are clearly intended: "
            prompt += vocabulary.joined(separator: ", ") + "."
        }
        return prompt
    }
}
