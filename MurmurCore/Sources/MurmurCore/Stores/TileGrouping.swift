import Foundation

/// Grouping decisions for the beta springboard: what a two-conversation drop
/// produces, and how folder anchor weights accumulate. Pure — no stores, no UI.
public enum TileGrouping {

    // MARK: Weighting knobs
    //
    // These decide how strongly a hand-made grouping steers future Smart organize
    // suggestions. With the defaults below, one deliberately shared tag scores
    // 3.0 * 5 = 15, beating a folder-name keyword match (10); an incidental
    // co-occurrence scores 1.0 * 5 = 5, which does not.

    /// Seeded on a tag both conversations already carried.
    public static let sharedWeight: Double = 3.0
    /// Seeded on a tag only one of the two carried.
    public static let coOccurringWeight: Double = 1.0
    /// Ceiling an anchor can reach through repeated reinforcement.
    public static let maxWeight: Double = 10.0
    /// Converts anchor weight into SmartFolderOrganizer's integer score scale.
    public static let anchorScoreMultiplier: Double = 5.0

    public static let defaultFolderName = "New Folder"

    public struct Proposal: Equatable, Sendable {
        /// Folder name to create or merge into.
        public let suggestedName: String
        /// Anchor weights to seed on that folder.
        public let anchors: [String: Double]
        /// False when the name is a fallback and the UI should focus the name field.
        public let isConfident: Bool

        public init(suggestedName: String, anchors: [String: Double], isConfident: Bool) {
            self.suggestedName = suggestedName
            self.anchors = anchors
            self.isConfident = isConfident
        }
    }

    /// Decide the folder name and seed anchors for dropping one conversation onto another.
    public static func propose(_ a: [String], _ b: [String]) -> Proposal {
        let left = normalized(a)
        let right = normalized(b)
        let shared = orderedIntersection(left, right)

        var anchors: [String: Double] = [:]
        for tag in Set(left).union(right) { anchors[tag] = coOccurringWeight }
        for tag in shared { anchors[tag] = sharedWeight }

        guard let winner = shared.first else {
            return Proposal(suggestedName: defaultFolderName, anchors: anchors, isConfident: false)
        }
        return Proposal(suggestedName: FolderNaming.displayName(for: winner),
                        anchors: anchors, isConfident: true)
    }

    /// Fold a conversation's tags into a folder's anchors when it is dropped in.
    /// Monotonic — weights never decrease — and bounded by `maxWeight`.
    public static func reinforced(_ existing: [String: Double], with tags: [String]) -> [String: Double] {
        var result = existing
        for tag in normalized(tags) {
            result[tag] = min(maxWeight, (result[tag] ?? 0) + coOccurringWeight)
        }
        return result
    }

    /// Combine two anchor sets, keeping the stronger weight for each tag.
    public static func merged(_ a: [String: Double], _ b: [String: Double]) -> [String: Double] {
        a.merging(b) { max($0, $1) }
    }

    private static func normalized(_ tags: [String]) -> [String] {
        tags.map(NoteTagger.normalize).filter { !$0.isEmpty }
    }

    /// Shared tags ranked most significant first. NoteTagger emits tags in
    /// descending significance and the primary tag sits at index 0, so the
    /// earliest combined position wins. Name breaks exact ties so the result
    /// never depends on Set iteration order.
    private static func orderedIntersection(_ left: [String], _ right: [String]) -> [String] {
        let shared = Set(left).intersection(right)
        guard !shared.isEmpty else { return [] }
        func rank(_ tag: String) -> Int {
            (left.firstIndex(of: tag) ?? left.count) + (right.firstIndex(of: tag) ?? right.count)
        }
        return shared.sorted { rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1) }
    }
}
