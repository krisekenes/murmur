import Foundation

public struct PasteDecision: Sendable {
    public let ownedChangeCount: Int
    public init(ownedChangeCount: Int) { self.ownedChangeCount = ownedChangeCount }

    /// Restore the user's previous clipboard only if nothing has written to the
    /// pasteboard since we did (i.e. we still "own" it).
    public func shouldRestore(currentChangeCount: Int) -> Bool {
        currentChangeCount == ownedChangeCount
    }
}
