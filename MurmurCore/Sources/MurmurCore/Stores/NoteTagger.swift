import Foundation

/// Small, deterministic topic suggestions. No model download or network required.
public enum NoteTagger {
    public static func normalize(_ tag: String) -> String {
        tag.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "#" })
            .joined(separator: "-")
    }

    public static func suggestions(for content: String, existing: [String] = [], vocabulary: [String] = []) -> [String] {
        let words = Set(content.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !words.isEmpty else { return [] }
        let topics: [(String, Set<String>)] = [
            ("interview", ["interview", "interviews", "interviewing", "candidate", "recruiter", "hiring"]),
            ("meetings", ["meeting", "meetings", "agenda", "standup", "attendees"]),
            ("tasks", ["todo", "deadline", "tasks", "reminder", "action"]),
            ("ideas", ["idea", "ideas", "brainstorm", "concept"]),
            ("work", ["project", "client", "team", "roadmap", "stakeholder"]),
            ("travel", ["flight", "hotel", "itinerary", "vacation", "trip"]),
            ("learning", ["study", "course", "lecture", "research", "learn"]),
            ("engineering", ["code", "bug", "api", "deploy", "database", "swift"]),
            ("personal", ["journal", "family", "birthday", "weekend"])
        ]
        var scores: [String: Int] = [:]
        for (tag, keywords) in topics {
            let score = words.intersection(keywords).count
            if score > 0 { scores[tag] = score }
        }
        // Reuse the user's own tags when their words occur in the note.
        for raw in vocabulary {
            let tag = normalize(raw)
            let parts = Set(tag.split(separator: "-").map(String.init))
            if !parts.isEmpty && parts.isSubset(of: words) { scores[tag] = max(scores[tag] ?? 0, 2) }
        }
        for token in content.split(whereSeparator: { $0.isWhitespace }) where token.hasPrefix("#") {
            let tag = normalize(String(token.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })))
            if !tag.isEmpty { scores[tag] = 10 }
        }
        let excluded = Set(existing.map(normalize))
        return Array(scores.keys.filter { !excluded.contains($0) }.sorted {
            scores[$0] == scores[$1] ? $0 < $1 : scores[$0]! > scores[$1]!
        }.prefix(5))
    }
}
