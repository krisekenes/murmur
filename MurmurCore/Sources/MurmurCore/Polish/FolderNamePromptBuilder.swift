import Foundation

/// Builds the prompt that asks the local model to name a folder from the two
/// conversations dropped together, and sanitizes what comes back.
///
/// Pure and synchronous so the naming rules are testable without a model —
/// `PolishEngine` owns the generation, this owns the words and the cleanup.
public struct FolderNamePromptBuilder: Sendable {
    /// Hard ceiling on words in an accepted name. A model that ignores the
    /// instruction and writes a sentence is rejected, not truncated into
    /// nonsense.
    public let maxWords: Int
    /// Characters of each transcript sent as context. Keeps the prompt small
    /// enough to stay inside the naming timeout on a 2B model.
    public let excerptLength: Int

    public init(maxWords: Int = 3, excerptLength: Int = 400) {
        self.maxWords = maxWords
        self.excerptLength = excerptLength
    }

    /// Leading slice of a transcript, cut on a word boundary so the model never
    /// sees a half-word at the edge.
    public func excerpt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > excerptLength else { return trimmed }
        let cut = trimmed.prefix(excerptLength)
        guard let lastSpace = cut.lastIndex(where: { $0.isWhitespace }) else { return String(cut) }
        return String(cut[cut.startIndex..<lastSpace])
    }

    /// The user turn: both excerpts, labelled so the model can find the overlap.
    public func userPrompt(_ first: String, _ second: String) -> String {
        """
        Conversation A:
        \(excerpt(first))

        Conversation B:
        \(excerpt(second))
        """
    }

    /// Strip what a small model tends to wrap a name in, then accept or reject.
    /// Returns nil when the result is unusable, so the caller keeps its fallback
    /// rather than writing junk into the notebook.
    public func sanitize(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models love to answer in quotes, with a label, or with a trailing stop.
        if let colon = name.firstIndex(of: ":"), name[name.startIndex..<colon].count < 20 {
            name = String(name[name.index(after: colon)...])
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'`*.-—"))
        // A model that refused, explained itself, or emitted markdown is unusable.
        guard !name.isEmpty, !name.contains("\n") else { return nil }
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty, words.count <= maxWords else { return nil }
        // Never let the model hand back the placeholder it was told to replace.
        guard name.localizedCaseInsensitiveCompare(TileGrouping.defaultFolderName) != .orderedSame else {
            return nil
        }
        return words.map(\.capitalized).joined(separator: " ")
    }

    /// Instructions for the naming turn.
    ///
    /// Names the literal shared subject rather than a category — "Roadmap", not
    /// "Planning" — and always commits to a name, falling back to the closest
    /// umbrella when the two conversations share nothing obvious. `sanitize`
    /// stays as the safety net for output that ignores these rules entirely.
    public func systemPrompt() -> String {
        """
        You name folders. Two dictated conversations were just grouped together. \
        Output ONLY the folder name and nothing else:
        - Name the specific subject both conversations share. Prefer the literal \
        topic ("Roadmap", "Interviews", "Lease") over a broad category \
        ("Planning", "Hiring", "Admin").
        - Use a noun phrase of 1 to \(maxWords) words in Title Case. No verbs, no \
        punctuation, no quotes, no explanation.
        - If they share no obvious subject, name the closest umbrella that covers \
        both. Always answer with a name.
        - Never answer with "\(TileGrouping.defaultFolderName)", a sentence, or markdown.
        """
    }
}
