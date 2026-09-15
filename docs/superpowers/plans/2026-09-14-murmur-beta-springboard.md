# Murmur Beta Springboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toggleable Beta view to Murmur: a full-window springboard of conversation tiles that preview transcript text, carry a renameable primary tag as their "filename", and group into folders by dragging one onto another, persisting weighted anchor tags that steer Smart organize.

**Architecture:** Every rule that mutates persisted data lives in `MurmurCore` as a pure, unit-tested function; the SwiftUI beta view tree under `App/Sources/UI/Beta/` stays disposable. The classic feed is untouched and remains the default. All data-model changes are additive and backward-compatible.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, macOS 14 deployment target, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-14-murmur-beta-springboard-design.md`

## Global Constraints

- Swift language mode 6 with strict concurrency. Every new public type crossing an isolation boundary must be `Sendable`.
- Deployment target macOS 14.0. `.draggable` / `.dropDestination` are available; do not use APIs newer than macOS 14.
- `HistoryEntry` and `ScratchpadPage` must not gain or lose stored properties.
- Any new stored property on an existing `Codable` type must decode via `decodeIfPresent` with a default. Synthesized decoding of a new required key breaks existing user files.
- `MurmurCore` has no dependencies and imports only `Foundation`. No SwiftUI, no AppKit.
- The classic feed view (`FeedView`, `DictationDetailView`, `ScratchpadView`) keeps working unchanged. Beta defaults to off.
- Run core tests with `swift test --package-path MurmurCore`. Baseline is 39 tests passing; the count only grows.
- Regenerate the Xcode project with `xcodegen generate` after touching `project.yml`.
- Commit style is Conventional Commits, as in `feat(beta): ...`.

## Baseline

Confirmed green before starting: `swift test --package-path MurmurCore` reports `Executed 39 tests, with 0 failures`.

## File Structure

**Create — MurmurCore (pure logic, fully tested):**

| File | Responsibility |
|---|---|
| `MurmurCore/Sources/MurmurCore/Stores/FolderNaming.swift` | Single source of truth for turning a tag into a folder display name |
| `MurmurCore/Sources/MurmurCore/Stores/TileGrouping.swift` | Grouping proposal + anchor weighting knobs and arithmetic |
| `MurmurCore/Tests/MurmurCoreTests/NoteFolderMigrationTests.swift` | Guards the notebook decode path against data loss |
| `MurmurCore/Tests/MurmurCoreTests/TileGroupingTests.swift` | Grouping and weighting rules |

**Create — App (disposable playground UI):**

| File | Responsibility |
|---|---|
| `App/Sources/UI/Beta/ConversationRef.swift` | Drag payload + exported UTType |
| `App/Sources/UI/Beta/RenameableLabel.swift` | Inline rename field shared by both tiles |
| `App/Sources/UI/Beta/ConversationTile.swift` | One conversation: text preview + renameable label |
| `App/Sources/UI/Beta/FolderTile.swift` | One folder: 2x2 miniatures + honest counts |
| `App/Sources/UI/Beta/FolderNotesSection.swift` | "Also in this folder" notes list inside an open folder |
| `App/Sources/UI/Beta/SpringboardView.swift` | Grid, drill-in, search flattening, drop handling, undo bar |

**Modify:**

| File | Change |
|---|---|
| `MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift` | `NoteFolder.anchorTags` + custom decode; `createFolder(name:anchors:)`; `reinforceAnchors` |
| `MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift` | `setPrimaryTag(_:for:)` |
| `MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift` | Anchor ranking tier; adopt `FolderNaming` |
| `MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift` | `setPrimaryTag` coverage |
| `MurmurCore/Tests/MurmurCoreTests/NotebookStoreTests.swift` | Anchor seeding, merging, reinforcement |
| `MurmurCore/Tests/MurmurCoreTests/SmartFolderOrganizerTests.swift` | Anchor ranking coverage |
| `App/Sources/AppState.swift` | `betaMode`, grouping actions, grouping undo, folder counts |
| `App/Sources/UI/MainWindowView.swift` | Beta toggle in top bar; branch body on `betaMode` |
| `project.yml` | `UTExportedTypeDeclarations` for the drag payload type |

**Deviation from spec:** the spec named a `FolderDetailView.swift`. Splitting the grid across two files made the boundary worse, so `SpringboardView` renders the grid for both root and open-folder states, and `FolderNotesSection.swift` owns only the notes list. Same behavior, cleaner responsibility split.

---

### Task 1: Folder anchor tags with a safe decode path

This is the highest-risk change in the plan. `NoteFolder` currently uses synthesized `Codable`, and `NotebookStore.init` decodes the whole notebook with `try?` — on failure it copies the file aside as `.corrupt` and replaces it with a single blank page. A new *required* key would make every pre-existing `notebook.json` fail to decode and silently destroy the user's pages and folders. The hand-written `init(from:)` is what prevents that.

**Files:**
- Modify: `MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift:38-41`
- Test: `MurmurCore/Tests/MurmurCoreTests/NoteFolderMigrationTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `NoteFolder.anchorTags: [String: Double]`, and `NoteFolder.init(id:name:anchorTags:)` with `anchorTags` defaulted to `[:]`

- [ ] **Step 1: Write the failing tests**

Create `MurmurCore/Tests/MurmurCoreTests/NoteFolderMigrationTests.swift`:

```swift
import XCTest
@testable import MurmurCore

final class NoteFolderMigrationTests: XCTestCase {
    private func freshNotebookURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notebook.json")
    }

    private func setAsideFiles(besides url: URL) throws -> [String] {
        let directory = url.deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return names.filter { $0.hasSuffix(".corrupt") }
    }

    /// A v0.2.0 notebook has no anchorTags key. If decoding it throws, NotebookStore
    /// sets the file aside and replaces it with a single blank page — destroying the
    /// user's pages and folders. This test is the guard against that.
    func test_legacyNotebookWithoutAnchorTagsLoadsIntact() throws {
        let url = freshNotebookURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pageID = UUID()
        let folderID = UUID()
        let legacy = """
        {"pages":[{"id":"\(pageID.uuidString)","content":"keep me","updatedAt":760000000,\
        "folderID":"\(folderID.uuidString)","tags":["work"]}],\
        "currentID":"\(pageID.uuidString)",\
        "folders":[{"id":"\(folderID.uuidString)","name":"Interviews"}]}
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let store = NotebookStore(fileURL: url)

        XCTAssertEqual(store.pages.count, 1)
        XCTAssertEqual(store.pages[0].content, "keep me")
        XCTAssertEqual(store.pages[0].tags, ["work"])
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders[0].id, folderID)
        XCTAssertEqual(store.folders[0].name, "Interviews")
        XCTAssertEqual(store.folders[0].anchorTags, [:])
        XCTAssertEqual(try setAsideFiles(besides: url), [], "notebook must not be treated as corrupt")
    }

    func test_folderWithAnchorsRoundTripsThroughCodable() throws {
        let folder = NoteFolder(id: UUID(), name: "Interviews", anchorTags: ["interview": 3.0])
        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(NoteFolder.self, from: data)
        XCTAssertEqual(decoded, folder)
        XCTAssertEqual(decoded.anchorTags, ["interview": 3.0])
    }

    func test_folderDefaultsToNoAnchors() {
        XCTAssertEqual(NoteFolder(id: UUID(), name: "Work").anchorTags, [:])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MurmurCore --filter NoteFolderMigrationTests`
Expected: FAIL to compile with "extra argument 'anchorTags' in call" and "value of type 'NoteFolder' has no member 'anchorTags'".

- [ ] **Step 3: Add the property and the hand-written decoder**

In `MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift`, replace the whole `NoteFolder` declaration:

```swift
public struct NoteFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// Tags this folder is "about", weighted by how deliberately they were set.
    /// Seeded when conversations are grouped by hand, reinforced on later drops.
    public var anchorTags: [String: Double]

    private enum CodingKeys: String, CodingKey { case id, name, anchorTags }

    public init(id: UUID, name: String, anchorTags: [String: Double] = [:]) {
        self.id = id
        self.name = name
        self.anchorTags = anchorTags
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        // Synthesized decoding would make anchorTags required, failing every notebook
        // written before this feature — and NotebookStore replaces an unreadable
        // notebook with a blank page. decodeIfPresent is the data-loss guard.
        anchorTags = try values.decodeIfPresent([String: Double].self, forKey: .anchorTags) ?? [:]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path MurmurCore --filter NoteFolderMigrationTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Run the whole suite for regressions**

Run: `swift test --package-path MurmurCore`
Expected: PASS, 42 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift \
        MurmurCore/Tests/MurmurCoreTests/NoteFolderMigrationTests.swift
git commit -m "feat(core): add weighted anchorTags to NoteFolder with backward-compatible decode"
```

---

### Task 2: Primary tag as the tile filename

The springboard label is `entry.tags.first`. Renaming reorders the existing array instead of adding a stored property, so search, filters, and the existing tag editor keep working untouched.

**Files:**
- Modify: `MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift` (add after `removeTag`, around line 75)
- Test: `MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `NoteTagger.normalize(_:)`
- Produces: `HistoryStore.setPrimaryTag(_ tag: String, for id: UUID)`

- [ ] **Step 1: Write the failing tests**

Append to `MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift`, inside the existing `final class HistoryStoreTests: XCTestCase` body:

```swift
    private func primaryTagStore() throws -> (HistoryStore, UUID, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history.json")
        let store = try HistoryStore(fileURL: url)
        let id = UUID()
        store.append(HistoryEntry(id: id, raw: "r", polished: "p", createdAt: Date(),
                                  appName: "Murmur", tags: ["work", "interview", "tasks"]))
        return (store, id, url)
    }

    func test_setPrimaryTagMovesAnExistingTagToFrontWithoutDuplicating() throws {
        let (store, id, _) = try primaryTagStore()
        store.setPrimaryTag("interview", for: id)
        XCTAssertEqual(store.entries[0].tags, ["interview", "work", "tasks"])
    }

    func test_setPrimaryTagInsertsAnUnknownTagAtFront() throws {
        let (store, id, _) = try primaryTagStore()
        store.setPrimaryTag("screener", for: id)
        XCTAssertEqual(store.entries[0].tags, ["screener", "work", "interview", "tasks"])
    }

    func test_setPrimaryTagNormalizesInput() throws {
        let (store, id, _) = try primaryTagStore()
        store.setPrimaryTag("#Job Interview", for: id)
        XCTAssertEqual(store.entries[0].tags.first, "job-interview")
    }

    func test_setPrimaryTagIgnoresBlankInput() throws {
        let (store, id, _) = try primaryTagStore()
        store.setPrimaryTag("   ", for: id)
        XCTAssertEqual(store.entries[0].tags, ["work", "interview", "tasks"])
    }

    func test_setPrimaryTagIsIdempotent() throws {
        let (store, id, _) = try primaryTagStore()
        store.setPrimaryTag("interview", for: id)
        store.setPrimaryTag("interview", for: id)
        XCTAssertEqual(store.entries[0].tags, ["interview", "work", "tasks"])
    }

    func test_setPrimaryTagPersists() throws {
        let (store, id, url) = try primaryTagStore()
        store.setPrimaryTag("interview", for: id)
        let reloaded = try HistoryStore(fileURL: url)
        XCTAssertEqual(reloaded.entries[0].tags.first, "interview")
    }

    func test_setPrimaryTagIgnoresUnknownEntry() throws {
        let (store, _, _) = try primaryTagStore()
        store.setPrimaryTag("interview", for: UUID())
        XCTAssertEqual(store.entries[0].tags, ["work", "interview", "tasks"])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MurmurCore --filter HistoryStoreTests`
Expected: FAIL to compile with "value of type 'HistoryStore' has no member 'setPrimaryTag'".

- [ ] **Step 3: Implement `setPrimaryTag`**

In `MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift`, add directly after `removeTag(_:from:)`:

```swift
    /// Promote a tag to index 0 — the springboard shows `tags.first` as the
    /// conversation's filename. Reordering avoids a new stored property, so
    /// search, filters, and the tag editor keep working unchanged.
    public func setPrimaryTag(_ tag: String, for id: UUID) {
        let tag = NoteTagger.normalize(tag)
        guard !tag.isEmpty, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].tags.first != tag else { return }
        entries[index].tags.removeAll { $0 == tag }
        entries[index].tags.insert(tag, at: 0)
        persist()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path MurmurCore --filter HistoryStoreTests`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path MurmurCore`
Expected: PASS, 49 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift \
        MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift
git commit -m "feat(core): promote a conversation tag to primary with setPrimaryTag"
```

---

### Task 3: Pure grouping and weighting logic

The heart of the feature. `TileGrouping` decides what a two-conversation drop produces; `FolderNaming` becomes the single source of truth for tag-to-folder-name conversion, which `SmartFolderOrganizer` currently owns privately. Extracting it keeps drag-grouping and Smart organize from drifting apart on naming.

> **Decision point for the repo owner.** The four constants at the top of `TileGrouping` decide how aggressively a hand-made grouping steers future auto-filing, and they compound across every grouping you ever make. The values below are a working, tested default — a deliberate grouping (3.0 x 5 = 15) beats a folder-name keyword match (10), while an incidental co-occurrence (1.0 x 5 = 5) does not. Raise `sharedWeight` or `anchorScoreMultiplier` for a pushier assistant; lower them to keep keyword matching in charge. Adjust before implementing and the tests in Step 1 adjust with them.

**Files:**
- Create: `MurmurCore/Sources/MurmurCore/Stores/FolderNaming.swift`
- Create: `MurmurCore/Sources/MurmurCore/Stores/TileGrouping.swift`
- Modify: `MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift:27-30` and `:50`
- Test: `MurmurCore/Tests/MurmurCoreTests/TileGroupingTests.swift`

**Interfaces:**
- Consumes: `NoteTagger.normalize(_:)`
- Produces:
  - `FolderNaming.displayName(for tag: String) -> String`
  - `TileGrouping.Proposal` with `suggestedName: String`, `anchors: [String: Double]`, `isConfident: Bool`
  - `TileGrouping.propose(_ a: [String], _ b: [String]) -> Proposal`
  - `TileGrouping.reinforced(_ existing: [String: Double], with tags: [String]) -> [String: Double]`
  - `TileGrouping.merged(_ a: [String: Double], _ b: [String: Double]) -> [String: Double]`
  - `TileGrouping.defaultFolderName: String`, `.sharedWeight`, `.coOccurringWeight`, `.maxWeight`, `.anchorScoreMultiplier`

- [ ] **Step 1: Write the failing tests**

Create `MurmurCore/Tests/MurmurCoreTests/TileGroupingTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MurmurCore --filter TileGroupingTests`
Expected: FAIL to compile with "cannot find 'TileGrouping' in scope" and "cannot find 'FolderNaming' in scope".

- [ ] **Step 3: Create `FolderNaming`**

Create `MurmurCore/Sources/MurmurCore/Stores/FolderNaming.swift`:

```swift
import Foundation

/// Turns a tag into a folder display name. Shared so that dragging two
/// conversations together and Smart organize never disagree on what to call
/// the same topic.
public enum FolderNaming {
    static let topicNames = ["interview": "Interviews", "meetings": "Meetings", "tasks": "Tasks",
                             "ideas": "Ideas", "work": "Work", "travel": "Travel", "learning": "Learning",
                             "engineering": "Engineering", "personal": "Personal"]

    public static func displayName(for tag: String) -> String {
        let tag = NoteTagger.normalize(tag)
        return topicNames[tag] ?? tag.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
```

- [ ] **Step 4: Create `TileGrouping`**

Create `MurmurCore/Sources/MurmurCore/Stores/TileGrouping.swift`:

```swift
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
```

- [ ] **Step 5: Point `SmartFolderOrganizer` at `FolderNaming`**

In `MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift`, delete the local `topicNames` constant (the first three lines of `suggestions`):

```swift
        let topicNames = ["interview": "Interviews", "meetings": "Meetings", "tasks": "Tasks",
                          "ideas": "Ideas", "work": "Work", "travel": "Travel", "learning": "Learning",
                          "engineering": "Engineering", "personal": "Personal"]
```

and replace the name lookup near the end of the same function:

```swift
            let name = topicNames[topic] ?? topic.replacingOccurrences(of: "-", with: " ").capitalized
```

with:

```swift
            let name = FolderNaming.displayName(for: topic)
```

This is a pure refactor — the existing `SmartFolderOrganizerTests` prove no behavior change.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path MurmurCore --filter TileGroupingTests`
Expected: PASS, 12 tests.

- [ ] **Step 7: Run the whole suite**

Run: `swift test --package-path MurmurCore`
Expected: PASS, 61 tests, 0 failures. The pre-existing `SmartFolderOrganizerTests` must still pass unchanged — that is the proof the naming refactor was behavior-preserving.

- [ ] **Step 8: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/FolderNaming.swift \
        MurmurCore/Sources/MurmurCore/Stores/TileGrouping.swift \
        MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift \
        MurmurCore/Tests/MurmurCoreTests/TileGroupingTests.swift
git commit -m "feat(core): add TileGrouping proposals and shared FolderNaming"
```

---

### Task 4: Seed and reinforce anchors in NotebookStore

`createFolder` already returns the existing folder on a case-insensitive name match — that is what makes grouping under an existing name merge instead of spawning "Interviews 2". This task preserves that and makes merging reinforce anchors rather than overwrite them.

**Files:**
- Modify: `MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift:123-135` (`createFolder`)
- Test: `MurmurCore/Tests/MurmurCoreTests/NotebookStoreTests.swift`

**Interfaces:**
- Consumes: `TileGrouping.merged(_:_:)`, `TileGrouping.reinforced(_:with:)`, `NoteFolder.init(id:name:anchorTags:)`
- Produces:
  - `NotebookStore.createFolder(name: String, anchors: [String: Double] = [:]) -> UUID?`
  - `NotebookStore.reinforceAnchors(_ folderID: UUID, with tags: [String])`

- [ ] **Step 1: Write the failing tests**

Append to `MurmurCore/Tests/MurmurCoreTests/NotebookStoreTests.swift`, inside the existing `final class NotebookStoreTests: XCTestCase` body:

```swift
    private func anchorStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notebook.json")
    }

    func test_createFolderSeedsAndPersistsAnchors() throws {
        let url = anchorStoreURL()
        let store = NotebookStore(fileURL: url)
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))

        let reloaded = NotebookStore(fileURL: url)
        XCTAssertEqual(reloaded.folders.first { $0.id == id }?.anchorTags, ["interview": 3.0])
    }

    func test_createFolderWithExistingNameMergesAnchorsKeepingTheStronger() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let first = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0, "work": 1.0]))
        let second = try XCTUnwrap(store.createFolder(name: "interviews", anchors: ["interview": 1.0, "tasks": 2.0]))

        XCTAssertEqual(first, second, "a case-insensitive name match must merge, not duplicate")
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders[0].anchorTags, ["interview": 3.0, "work": 1.0, "tasks": 2.0])
    }

    func test_createFolderWithoutAnchorsLeavesExistingAnchorsUntouched() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        XCTAssertEqual(store.createFolder(name: "Interviews"), id)
        XCTAssertEqual(store.folders[0].anchorTags, ["interview": 3.0])
    }

    func test_reinforceAnchorsRaisesWeightsAndPersists() throws {
        let url = anchorStoreURL()
        let store = NotebookStore(fileURL: url)
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        store.reinforceAnchors(id, with: ["interview", "screener"])

        let reloaded = NotebookStore(fileURL: url)
        let anchors = try XCTUnwrap(reloaded.folders.first { $0.id == id }?.anchorTags)
        XCTAssertEqual(anchors["interview"], 4.0)
        XCTAssertEqual(anchors["screener"], 1.0)
    }

    func test_reinforceAnchorsIgnoresAnUnknownFolder() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        store.reinforceAnchors(UUID(), with: ["anything"])
        XCTAssertEqual(store.folders.first { $0.id == id }?.anchorTags, ["interview": 3.0])
    }

    func test_deletingAFolderRemovesItsAnchors() throws {
        let store = NotebookStore(fileURL: anchorStoreURL())
        let id = try XCTUnwrap(store.createFolder(name: "Interviews", anchors: ["interview": 3.0]))
        store.deleteFolder(id)
        XCTAssertTrue(store.folders.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MurmurCore --filter NotebookStoreTests`
Expected: FAIL to compile with "extra argument 'anchors' in call" and "value of type 'NotebookStore' has no member 'reinforceAnchors'".

- [ ] **Step 3: Extend `createFolder` and add `reinforceAnchors`**

In `MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift`, replace the whole `createFolder(name:)` method:

```swift
    /// Creates a folder, or returns the existing one with the same name so that
    /// grouping under a name you already use merges instead of duplicating.
    /// Merging reinforces the existing anchors rather than replacing them.
    @discardableResult
    public func createFolder(name: String, anchors: [String: Double] = [:]) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let index = folders.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            if !anchors.isEmpty {
                folders[index].anchorTags = TileGrouping.merged(folders[index].anchorTags, anchors)
                persist()
            }
            return folders[index].id
        }
        let folder = NoteFolder(id: UUID(), name: name, anchorTags: anchors)
        folders.append(folder)
        persist()
        return folder.id
    }

    /// Strengthen a folder's anchors when a conversation is dropped into it.
    public func reinforceAnchors(_ folderID: UUID, with tags: [String]) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].anchorTags = TileGrouping.reinforced(folders[index].anchorTags, with: tags)
        persist()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path MurmurCore --filter NotebookStoreTests`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path MurmurCore`
Expected: PASS, 67 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift \
        MurmurCore/Tests/MurmurCoreTests/NotebookStoreTests.swift
git commit -m "feat(core): seed and reinforce folder anchor tags in NotebookStore"
```

---

### Task 5: Let anchors outrank keyword guesses in Smart organize

The payoff for the whole weighting model: a folder you built by hand should beat one the tagger merely name-matched. A folder with empty `anchorTags` must score exactly as it does today, so untouched v0.2.0 folders behave identically.

**Files:**
- Modify: `MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift:31-42`
- Test: `MurmurCore/Tests/MurmurCoreTests/SmartFolderOrganizerTests.swift`

**Interfaces:**
- Consumes: `TileGrouping.anchorScoreMultiplier`, `NoteFolder.anchorTags`, `NotebookStore.createFolder(name:anchors:)`
- Produces: no new symbols; changes the ranking inside `SmartFolderOrganizer.suggestions(entries:folders:)`

- [ ] **Step 1: Write the failing tests**

Append to `MurmurCore/Tests/MurmurCoreTests/SmartFolderOrganizerTests.swift`, inside the existing class body. It already has `entry(_:tags:folderID:)` and `stores()` helpers — reuse them.

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MurmurCore --filter SmartFolderOrganizerTests`
Expected: FAIL. `test_anchorWeightOutranksAFolderNameMatch` fails because "Screeners" scores 0 today and is filtered out entirely, so the suggestion is "Recruiting".

- [ ] **Step 3: Add the anchor tier to the ranking**

In `MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift`, replace the body of the `ranked` closure:

```swift
            let ranked = folders.compactMap { folder -> (NoteFolder, Int, String)? in
                let nameWords = words(folder.name)
                let nameMatch = !nameWords.isEmpty && nameWords.isSubset(of: contentWords)
                let filed = entries.filter { $0.folderID == folder.id }
                let matchingTags = Set(filed.flatMap(\.tags)).intersection(tags)
                // A folder built by hand carries anchor weights; one the tagger merely
                // name-matched does not. Folders with no anchors score exactly as before.
                let anchorSum = tags.reduce(0.0) { $0 + (folder.anchorTags[$1] ?? 0) }
                let anchorScore = Int((anchorSum * TileGrouping.anchorScoreMultiplier).rounded())
                let score = anchorScore + (nameMatch ? 10 : 0) + min(matchingTags.count, 5)
                guard score > 0 else { return nil }
                let reason: String
                if anchorScore > 0,
                   let anchor = tags.max(by: { (folder.anchorTags[$0] ?? 0) < (folder.anchorTags[$1] ?? 0) }) {
                    reason = "Grouped by hand around #\(anchor)"
                } else if nameMatch {
                    reason = "Matches folder name"
                } else {
                    reason = "Shares tags with conversations in this folder"
                }
                return (folder, score, reason)
            }.sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
```

The existing ambiguity guard below it (`guard ranked.count == 1 || best.1 > ranked[1].1`) is unchanged and now also covers tied anchor scores.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path MurmurCore --filter SmartFolderOrganizerTests`
Expected: PASS, including the 5 pre-existing tests.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path MurmurCore`
Expected: PASS, 71 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift \
        MurmurCore/Tests/MurmurCoreTests/SmartFolderOrganizerTests.swift
git commit -m "feat(core): rank folder anchors above keyword matches in Smart organize"
```

---

## App-layer tasks

Tasks 6-10 touch SwiftUI. This repo has no app-target test harness — all 71 tests live in `MurmurCore` — so these tasks verify by compiling clean and by the manual checklist in Task 10. Do not add a UI test harness; the spec explicitly rules it out.

Debug build command used throughout:

```bash
xcodegen generate && xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/debug \
  -disableAutomaticPackageResolution -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
```

---

### Task 6: AppState beta mode, grouping actions, and undo

**Files:**
- Modify: `App/Sources/AppState.swift` (add a `// MARK: - Beta springboard` section after `undoConversationOrganization`, around line 115)

**Interfaces:**
- Consumes: `TileGrouping.propose(_:_:)`, `NotebookStore.createFolder(name:anchors:)`, `NotebookStore.reinforceAnchors(_:with:)`, `HistoryStore.setPrimaryTag(_:for:)`
- Produces:
  - `AppState.betaMode: Bool`
  - `AppState.GroupingResult` with `folderID: UUID`, `shouldPromptForName: Bool`
  - `AppState.groupConversations(_ first: UUID, _ second: UUID, name: String?) -> GroupingResult?`
  - `AppState.fileConversation(_ id: UUID, into folderID: UUID)`
  - `AppState.setPrimaryConversationTag(_ tag: String, id: UUID)`
  - `AppState.undoLastGrouping()`
  - `AppState.lastGroupingSummary: String?`
  - `AppState.conversationCount(inFolder: UUID) -> Int`, `AppState.noteCount(inFolder: UUID) -> Int`

- [ ] **Step 1: Add the beta section to `AppState`**

In `App/Sources/AppState.swift`, insert after `undoConversationOrganization()`:

```swift
    // MARK: - Beta springboard

    @Published public var betaMode: Bool = UserDefaults.standard.bool(forKey: "betaMode") {
        didSet { UserDefaults.standard.set(betaMode, forKey: "betaMode") }
    }

    public struct GroupingResult: Equatable, Sendable {
        public let folderID: UUID
        /// True when the name was a fallback and the UI should focus the name field.
        public let shouldPromptForName: Bool
    }

    /// Non-nil while the last grouping can still be undone this session.
    @Published public var lastGroupingSummary: String?
    private var lastGrouping: (folderID: UUID, movedIDs: [UUID], folderWasCreated: Bool)?

    /// Drop one conversation onto another: create or merge a folder and move both in.
    /// Passing a name overrides the proposal, which is how inline renaming commits.
    @discardableResult
    public func groupConversations(_ first: UUID, _ second: UUID, name: String? = nil) -> GroupingResult? {
        guard first != second,
              let a = historyEntries.first(where: { $0.id == first }),
              let b = historyEntries.first(where: { $0.id == second }) else { return nil }
        let proposal = TileGrouping.propose(a.tags, b.tags)
        let folderName = (name ?? proposal.suggestedName).trimmingCharacters(in: .whitespacesAndNewlines)
        // Record whether the folder already existed, so undo only removes what we made.
        let existed = notebook.folders.contains {
            $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        }
        guard let folderID = notebook.createFolder(name: folderName, anchors: proposal.anchors) else { return nil }
        history.move(a.id, to: folderID)
        history.move(b.id, to: folderID)
        lastGrouping = (folderID, [a.id, b.id], !existed)
        lastGroupingSummary = "Grouped 2 into \(folderName)"
        folders = notebook.folders
        refreshHistory()
        return GroupingResult(folderID: folderID,
                              shouldPromptForName: name == nil && !proposal.isConfident)
    }

    /// Drop a conversation onto an existing folder: file it and strengthen the anchors.
    public func fileConversation(_ id: UUID, into folderID: UUID) {
        guard let entry = historyEntries.first(where: { $0.id == id }),
              entry.folderID != folderID,
              folders.contains(where: { $0.id == folderID }) else { return }
        notebook.reinforceAnchors(folderID, with: entry.tags)
        history.move(id, to: folderID)
        folders = notebook.folders
        refreshHistory()
    }

    /// Rename a tile: promote a tag to the front, where the springboard reads it.
    public func setPrimaryConversationTag(_ tag: String, id: UUID) {
        history.setPrimaryTag(tag, for: id)
        refreshHistory()
    }

    /// Reverse the last grouping. Unfiles only entries still in that folder, so a
    /// manual move made afterwards survives. Removes the folder only if this action
    /// created it and nothing — conversation or scratchpad note — remains inside.
    public func undoLastGrouping() {
        guard let grouping = lastGrouping else { return }
        for id in grouping.movedIDs
        where history.entries.first(where: { $0.id == id })?.folderID == grouping.folderID {
            history.move(id, to: nil)
        }
        if grouping.folderWasCreated,
           !history.entries.contains(where: { $0.folderID == grouping.folderID }),
           !notebook.pages.contains(where: { $0.folderID == grouping.folderID }) {
            notebook.deleteFolder(grouping.folderID)
        }
        lastGrouping = nil
        lastGroupingSummary = nil
        folders = notebook.folders
        refreshHistory()
    }

    /// NoteFolder is shared with the scratchpad, so a folder tile must count both
    /// kinds of content or it misreports what deleting the folder would touch.
    public func conversationCount(inFolder id: UUID) -> Int {
        historyEntries.reduce(0) { $0 + ($1.folderID == id ? 1 : 0) }
    }

    public func noteCount(inFolder id: UUID) -> Int {
        pages.reduce(0) { $0 + ($1.folderID == id ? 1 : 0) }
    }
```

- [ ] **Step 2: Verify it compiles**

Run the Debug build command above.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Sources/AppState.swift
git commit -m "feat(beta): add beta mode, grouping actions, and grouping undo to AppState"
```

---

### Task 7: Drag payload and exported type

Carrying the text alongside the id means dragging a tile out of Murmur into TextEdit or Slack pastes the transcript rather than a UUID.

**Files:**
- Create: `App/Sources/UI/Beta/ConversationRef.swift`
- Modify: `project.yml:44-49` (the `info.properties` block)

**Interfaces:**
- Consumes: `HistoryEntry`
- Produces: `ConversationRef` conforming to `Transferable`, with `init(entry: HistoryEntry)`, `id: UUID`, `text: String`; and `UTType.murmurConversation`

- [ ] **Step 1: Create the payload type**

Create `App/Sources/UI/Beta/ConversationRef.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import MurmurCore

extension UTType {
    /// Declared in project.yml under UTExportedTypeDeclarations.
    static let murmurConversation = UTType(exportedAs: "com.murmur.conversation")
}

/// Drag payload for springboard tiles. Carrying the text as well as the id means a
/// tile dragged out of Murmur pastes the transcript instead of a bare UUID.
struct ConversationRef: Codable, Transferable, Sendable {
    let id: UUID
    let text: String

    init(entry: HistoryEntry) {
        id = entry.id
        text = entry.polished.isEmpty ? entry.raw : entry.polished
    }

    static var transferRepresentation: some TransferRepresentation {
        // First representation wins for in-app drops; the proxy serves other apps.
        CodableRepresentation(contentType: .murmurConversation)
        ProxyRepresentation(exporting: \.text)
    }
}
```

- [ ] **Step 2: Declare the exported type**

In `project.yml`, inside `targets.Murmur.info.properties`, after the `CFBundleVersion` line, add:

```yaml
        UTExportedTypeDeclarations:
          - UTTypeIdentifier: com.murmur.conversation
            UTTypeDescription: Murmur Conversation
            UTTypeConformsTo:
              - public.data
```

- [ ] **Step 3: Verify it compiles and the declaration landed**

Run the Debug build command above.
Expected: `** BUILD SUCCEEDED **`.

Then confirm the plist actually carries the type:

```bash
plutil -extract UTExportedTypeDeclarations xml1 -o - \
  .build/debug/Build/Products/Debug/Murmur.app/Contents/Info.plist
```
Expected: XML containing `com.murmur.conversation`.

**If this fails**, fall back to the spec's documented alternative: drop `ConversationRef.swift` and the `project.yml` block, use `.draggable(entry.id.uuidString)` with `.dropDestination(for: String.self)` throughout Tasks 8 and 9, and parse the UUID with `UUID(uuidString:)` at each drop site. In-app behavior is identical; only out-of-app dragging is lost.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/UI/Beta/ConversationRef.swift project.yml
git commit -m "feat(beta): add conversation drag payload with exported UTType"
```

---

### Task 8: Tile views

The visual vocabulary of the springboard. Both tiles share the same footprint so the grid stays on a rhythm, and both put a renameable label under a preview — the Finder shape. The rename behavior lives in one view so the two tiles cannot drift apart on what Return, Escape, blur, and empty input mean.

**Files:**
- Create: `App/Sources/UI/Beta/RenameableLabel.swift`
- Create: `App/Sources/UI/Beta/ConversationTile.swift`
- Create: `App/Sources/UI/Beta/FolderTile.swift`
- Modify: `App/Sources/UI/Theme.swift`

**Interfaces:**
- Consumes: `HistoryEntry`, `NoteFolder`, `Theme.accent`
- Produces:
  - `Theme.canvas: Color`
  - `RenameableLabel(text:editSeed:font:color:beginsEditing:onCommit:onEditingEnded:)`
  - `ConversationTile(entry:isDropTarget:onOpen:onRename:)`
  - `FolderTile(folder:previews:conversationCount:noteCount:isDropTarget:beginsRenaming:onOpen:onRename:onRenameEnded:)`

- [ ] **Step 1: Add the canvas color to Theme**

Replace `App/Sources/UI/Theme.swift` with:

```swift
import SwiftUI

public enum Theme {
    public static let accent = Color(red: 0.96, green: 0.65, blue: 0.14) // ~#F5A623 warm amber
    public static let canvas = Color(red: 0.05, green: 0.05, blue: 0.06) // main window background
    public static let pillSize = CGSize(width: 280, height: 56)
}
```

- [ ] **Step 2: Create `RenameableLabel`**

Note `text` and `editSeed` are deliberately separate: a conversation tile *displays* `#tasks` or a time stamp but must *edit* the bare tag `tasks`. The unchanged-value guard compares against `editSeed`, not the display text.

Create `App/Sources/UI/Beta/RenameableLabel.swift`:

```swift
import SwiftUI

/// The editable name under a springboard tile. Owns every rule about what renaming
/// means — commit on Return or blur, revert on Escape or empty — so conversation
/// tiles and folder tiles cannot drift apart on the behavior.
struct RenameableLabel: View {
    /// What the label shows when idle, e.g. "#tasks" or "9:42 PM".
    let text: String
    /// What the field starts with when editing begins, e.g. the bare tag "tasks".
    let editSeed: String
    let font: Font
    let color: Color
    /// Set when a tile was just created with a fallback name and wants focus.
    let beginsEditing: Bool
    let onCommit: (String) -> Void
    let onEditingEnded: () -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .multilineTextAlignment(.center)
                    .focused($fieldFocused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
                    .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.12)))
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
                    .help("Click to rename")
            }
        }
        .frame(width: 118)
        .onAppear { if beginsEditing { beginEditing() } }
        .onChange(of: beginsEditing) { _, begins in if begins { beginEditing() } }
    }

    private func beginEditing() {
        draft = editSeed
        editing = true
        fieldFocused = true
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        onEditingEnded()
        guard !value.isEmpty, value != editSeed else { return }   // empty or unchanged reverts
        onCommit(value)
    }

    /// Clearing the draft first makes the commit triggered by losing focus a no-op.
    private func cancel() {
        draft = ""
        editing = false
        onEditingEnded()
    }
}
```

- [ ] **Step 3: Create `ConversationTile`**

Create `App/Sources/UI/Beta/ConversationTile.swift`:

```swift
import SwiftUI
import MurmurCore

/// One conversation on the springboard: a preview of what was actually said, with
/// a renameable primary tag beneath it the way a file sits under its name.
struct ConversationTile: View {
    let entry: HistoryEntry
    let isDropTarget: Bool
    let onOpen: () -> Void
    let onRename: (String) -> Void

    @State private var hover = false

    private var previewText: String {
        let text = entry.polished.isEmpty ? entry.raw : entry.polished
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Untagged conversations fall back to a time stamp until you name them.
    private var label: String {
        entry.tags.first.map { "#" + $0 }
            ?? entry.createdAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 6) {
            preview
            RenameableLabel(
                text: label,
                editSeed: entry.tags.first ?? "",
                font: .system(size: 10),
                color: entry.tags.isEmpty ? Color.secondary : Theme.accent.opacity(0.9),
                beginsEditing: false,
                onCommit: onRename,
                onEditingEnded: {}
            )
        }
        .frame(width: 132)
    }

    private var preview: some View {
        Text(previewText)
            .font(.system(size: 10))
            .lineSpacing(1.5)
            .foregroundStyle(.primary.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .frame(width: 118, height: 92, alignment: .topLeading)
            .clipped()
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(hover ? 0.09 : 0.05)))
            .overlay(alignment: .bottom) {
                // Fade the clipped text instead of slicing a line of glyphs in half.
                LinearGradient(colors: [.clear, Theme.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isDropTarget ? Theme.accent : .white.opacity(0.09),
                                  lineWidth: isDropTarget ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.14), value: hover)
            .animation(.easeOut(duration: 0.12), value: isDropTarget)
            .accessibilityLabel(Text("Conversation: " + String(previewText.prefix(80))))
    }
}
```

- [ ] **Step 4: Create `FolderTile`**

Create `App/Sources/UI/Beta/FolderTile.swift`:

```swift
import SwiftUI
import MurmurCore

/// A folder on the springboard: a 2x2 of the newest conversations inside, iOS-style.
/// Counts include scratchpad pages, because NoteFolder is a namespace shared with
/// the notebook and a conversations-only count would misreport the folder.
struct FolderTile: View {
    let folder: NoteFolder
    /// Up to four conversation previews, newest first.
    let previews: [String]
    let conversationCount: Int
    let noteCount: Int
    let isDropTarget: Bool
    /// Set right after a drop created this folder with a fallback name.
    let beginsRenaming: Bool
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onRenameEnded: () -> Void

    @State private var hover = false

    private var countLabel: String {
        noteCount == 0
            ? "\(conversationCount)"
            : "\(conversationCount) · \(noteCount) note\(noteCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 6) {
            previewGrid
            RenameableLabel(
                text: folder.name,
                editSeed: folder.name,
                font: .system(size: 10, weight: .medium),
                color: .primary,
                beginsEditing: beginsRenaming,
                onCommit: onRename,
                onEditingEnded: onRenameEnded
            )
            Text(countLabel)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(width: 132)
    }

    private var previewGrid: some View {
        VStack(spacing: 5) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { column in
                        miniature(at: row * 2 + column)
                    }
                }
            }
        }
        .padding(9)
        .frame(width: 118, height: 92)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(hover ? 0.10 : 0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(isDropTarget ? Theme.accent : .white.opacity(0.09),
                              lineWidth: isDropTarget ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .accessibilityLabel(Text("Folder \(folder.name), \(countLabel)"))
    }

    private func miniature(at index: Int) -> some View {
        Group {
            if index < previews.count {
                Text(previews[index])
                    .font(.system(size: 5))
                    .lineSpacing(0.5)
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.10)))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.04))
            }
        }
        .clipped()
    }
}
```

- [ ] **Step 5: Verify it compiles**

Run the Debug build command above.
Expected: `** BUILD SUCCEEDED **`. The tiles are not yet referenced anywhere; this step only proves they compile.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/UI/Beta/RenameableLabel.swift App/Sources/UI/Beta/ConversationTile.swift \
        App/Sources/UI/Beta/FolderTile.swift App/Sources/UI/Theme.swift
git commit -m "feat(beta): add springboard tiles with a shared renameable label"
```

---

### Task 9: The springboard itself

Grid, drill-in, search flattening, all five drop behaviors, and the undo bar.

**Files:**
- Create: `App/Sources/UI/Beta/FolderNotesSection.swift`
- Create: `App/Sources/UI/Beta/SpringboardView.swift`

**Interfaces:**
- Consumes: `ConversationTile`, `FolderTile`, `ConversationRef`, `DictationDetailView`, `ScratchpadView`, `Theme.canvas`, and from `AppState`: `groupConversations`, `fileConversation`, `moveConversation`, `setPrimaryConversationTag`, `renameFolder`, `selectPage`, `undoLastGrouping`, `lastGroupingSummary`, `conversationCount(inFolder:)`, `noteCount(inFolder:)`
- Produces: `SpringboardView(state:search:)`, `FolderNotesSection(state:folder:onOpenScratchpad:)`

- [ ] **Step 1: Create `FolderNotesSection`**

Create `App/Sources/UI/Beta/FolderNotesSection.swift`:

```swift
import SwiftUI
import MurmurCore

/// Folders are a shared namespace — the scratchpad files pages into the same folders
/// as conversations. The springboard doesn't make notes draggable, so it lists them
/// here rather than pretending the folder holds conversations only.
struct FolderNotesSection: View {
    @ObservedObject var state: AppState
    let folder: NoteFolder
    let onOpenScratchpad: () -> Void

    private var notes: [ScratchpadPage] {
        state.pages
            .filter { $0.folderID == folder.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALSO IN THIS FOLDER")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                ForEach(notes) { note in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(note.displayTitle)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Open") {
                            state.selectPage(note.id)
                            onOpenScratchpad()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }
            .padding(.top, 10)
        }
    }
}
```

- [ ] **Step 2: Create `SpringboardView`**

Create `App/Sources/UI/Beta/SpringboardView.swift`:

```swift
import SwiftUI
import MurmurCore

/// Beta springboard: conversations as tiles you drag together into folders.
/// Root shows unfiled conversations plus folder tiles; opening a folder shows its
/// conversations. Search flattens both, Finder-style.
struct SpringboardView: View {
    @ObservedObject var state: AppState
    @Binding var search: String

    @State private var openFolderID: UUID?
    @State private var dropTargetID: UUID?
    @State private var renamingFolderID: UUID?
    @State private var detailEntry: HistoryEntry?
    @State private var showingScratchpad = false

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var openFolder: NoteFolder? {
        openFolderID.flatMap { id in state.folders.first { $0.id == id } }
    }

    private func matches(_ entry: HistoryEntry) -> Bool {
        entry.polished.localizedCaseInsensitiveContains(search)
            || entry.raw.localizedCaseInsensitiveContains(search)
            || entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    /// `history.entries` is newest-first, so these stay newest-first for free.
    private var conversations: [HistoryEntry] {
        if isSearching { return state.historyEntries.filter(matches) }
        if let openFolderID { return state.historyEntries.filter { $0.folderID == openFolderID } }
        return state.historyEntries.filter { $0.folderID == nil }
    }

    /// Folders are hidden while searching so results read as one flat list.
    private var visibleFolders: [NoteFolder] {
        guard !isSearching, openFolderID == nil else { return [] }
        return state.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            if let summary = state.lastGroupingSummary { undoBar(summary) }
            Divider().opacity(0.5)
            grid
            footer
        }
        .background(Theme.canvas)
        .sheet(item: $detailEntry) { entry in
            DictationDetailView(
                state: state,
                entry: entry,
                onClose: { detailEntry = nil },
                onCopy: { copy(entry.polished.isEmpty ? entry.raw : entry.polished) },
                onSend: {
                    state.appendToScratchpad(entry.polished)
                    detailEntry = nil
                    showingScratchpad = true
                },
                onDelete: {
                    state.deleteDictation(id: entry.id)
                    detailEntry = nil
                }
            )
            .frame(minWidth: 460, minHeight: 420)
        }
        .sheet(isPresented: $showingScratchpad) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { showingScratchpad = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(10)
                ScratchpadView(state: state)
            }
            .frame(minWidth: 520, minHeight: 440)
        }
        .onChange(of: state.folders) { _, folders in
            // The open folder can be deleted from the scratchpad. Pop back out.
            if let id = openFolderID, !folders.contains(where: { $0.id == id }) { openFolderID = nil }
        }
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if conversations.isEmpty && visibleFolders.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 18)],
                              alignment: .leading, spacing: 20) {
                        ForEach(visibleFolders) { folder in folderTile(folder) }
                        ForEach(conversations) { entry in conversationTile(entry) }
                    }
                }
                if let folder = openFolder, !isSearching {
                    FolderNotesSection(state: state, folder: folder,
                                       onOpenScratchpad: { showingScratchpad = true })
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dropping on empty canvas inside a folder takes the conversation back out.
        .dropDestination(for: ConversationRef.self) { refs, _ in
            guard openFolderID != nil, let ref = refs.first else { return false }
            state.moveConversation(ref.id, to: nil)
            return true
        }
    }

    private func conversationTile(_ entry: HistoryEntry) -> some View {
        ConversationTile(
            entry: entry,
            isDropTarget: dropTargetID == entry.id,
            onOpen: { detailEntry = entry },
            onRename: { state.setPrimaryConversationTag($0, id: entry.id) }
        )
        .draggable(ConversationRef(entry: entry))
        .dropDestination(for: ConversationRef.self) { refs, _ in
            guard let ref = refs.first, ref.id != entry.id else { return false }
            guard let result = state.groupConversations(ref.id, entry.id) else { return false }
            openFolderID = nil
            if result.shouldPromptForName { renamingFolderID = result.folderID }
            return true
        } isTargeted: { targeted in
            if targeted { dropTargetID = entry.id }
            else if dropTargetID == entry.id { dropTargetID = nil }
        }
    }

    private func folderTile(_ folder: NoteFolder) -> some View {
        FolderTile(
            folder: folder,
            previews: state.historyEntries
                .filter { $0.folderID == folder.id }
                .prefix(4)
                .map { $0.polished.isEmpty ? $0.raw : $0.polished },
            conversationCount: state.conversationCount(inFolder: folder.id),
            noteCount: state.noteCount(inFolder: folder.id),
            isDropTarget: dropTargetID == folder.id,
            beginsRenaming: renamingFolderID == folder.id,
            onOpen: { openFolderID = folder.id },
            onRename: { _ = state.renameFolder(folder.id, name: $0) },
            onRenameEnded: { renamingFolderID = nil }
        )
        .dropDestination(for: ConversationRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            state.fileConversation(ref.id, into: folder.id)
            return true
        } isTargeted: { targeted in
            if targeted { dropTargetID = folder.id }
            else if dropTargetID == folder.id { dropTargetID = nil }
        }
    }

    // MARK: Chrome

    @ViewBuilder private var breadcrumb: some View {
        if isSearching {
            header { Text("Results for \u{201C}\(search)\u{201D}") }
        } else if let folder = openFolder {
            header {
                Button { openFolderID = nil } label: {
                    Label("All", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                // Dragging a tile onto the breadcrumb takes it out of the folder.
                .dropDestination(for: ConversationRef.self) { refs, _ in
                    guard let ref = refs.first else { return false }
                    state.moveConversation(ref.id, to: nil)
                    return true
                }
                Text("/").foregroundStyle(.tertiary)
                Text(folder.name).fontWeight(.semibold)
            }
        } else {
            header { Text("All conversations") }
        }
    }

    private func header<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
            Spacer()
            Text("\(conversations.count)").foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 22)
        .frame(height: 38)
    }

    private func undoBar(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus").foregroundStyle(Theme.accent)
            Text(summary)
            Text("·").foregroundStyle(.tertiary)
            Button("Undo") { state.undoLastGrouping() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(.white.opacity(0.04))
    }

    private var emptyState: some View {
        Text(state.historyEntries.isEmpty ? "No conversations yet" : "No matching conversations")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    private var footer: some View {
        HStack {
            Text("Drag one conversation onto another to group them")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button { showingScratchpad = true } label: {
                Label("Scratchpad", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run the Debug build command above.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/UI/Beta/SpringboardView.swift App/Sources/UI/Beta/FolderNotesSection.swift
git commit -m "feat(beta): add springboard grid with drag-to-group and folder drill-in"
```

---

### Task 10: Wire the toggle in and verify end to end

**Files:**
- Modify: `App/Sources/UI/MainWindowView.swift:19-28` (body) and `:84-90` (top bar)

**Interfaces:**
- Consumes: `SpringboardView(state:search:)`, `AppState.betaMode`
- Produces: nothing downstream; this is the last task

- [ ] **Step 1: Branch the body on `betaMode`**

In `App/Sources/UI/MainWindowView.swift`, replace the `HSplitView` block inside `body`:

```swift
            if state.betaMode {
                SpringboardView(state: state, search: $search)
            } else {
                HSplitView {
                    FeedView(state: state, search: $search, selectedID: $selectedID)
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 440)
                    rightPane
                        .frame(minWidth: 380)
                }
            }
```

- [ ] **Step 2: Add the toggle to the top bar**

In the same file, replace the existing Scratchpad button in `topBar` — the springboard carries its own, so it only belongs to the classic layout:

```swift
            if !state.betaMode {
                Button { selectedID = nil } label: {
                    Label("Scratchpad", systemImage: "books.vertical")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open editable scratchpad pages")
            }

            Toggle(isOn: $state.betaMode) {
                Text("Beta").font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.accent)
            .help("Switch between the classic feed and the springboard playground")
```

- [ ] **Step 3: Build and run**

```bash
xcodegen generate && xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/debug \
  -disableAutomaticPackageResolution -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
open .build/debug/Build/Products/Debug/Murmur.app
```

Expected: `** BUILD SUCCEEDED **`, app launches to the menu bar (it is `LSUIElement`), main window opens from the menu-bar icon.

- [ ] **Step 4: Back up real data before manual testing**

The beta view writes to live data. Snapshot it first so a bad drop is recoverable:

```bash
cp -R ~/Library/Application\ Support/Murmur ~/Library/Application\ Support/Murmur.backup-$(date +%Y%m%d-%H%M%S)
```

- [ ] **Step 5: Work the manual checklist**

Verify each, and note any that fail rather than moving on:

- [ ] Toggle Beta on — the springboard replaces the split view; toggle off — the classic feed returns unchanged
- [ ] Quit and relaunch — the toggle keeps its state
- [ ] Root grid shows folder tiles first (alphabetical), then unfiled conversations newest-first
- [ ] A conversation already in a folder does **not** appear at the root
- [ ] Tiles preview transcript text; an untagged conversation shows a time stamp label
- [ ] Drag a tagged conversation onto another sharing a tag — folder is created and named from the shared tag, no name prompt
- [ ] Drag two conversations with no shared tag — folder is named "New Folder" with the name field focused; typing renames it
- [ ] Drag a conversation onto an existing folder tile — it files in and the tile count increments
- [ ] Open a folder, drag a tile onto the "All" breadcrumb — it leaves the folder
- [ ] Open a folder, drag a tile onto empty canvas — it leaves the folder
- [ ] Drop a tile onto itself — nothing happens
- [ ] Click a tile label, rename it, press Return — label updates and survives relaunch
- [ ] Rename, then press Escape — reverts
- [ ] Rename to empty, then click away — reverts
- [ ] Rename a folder to an existing folder's name — reverts
- [ ] Group two conversations, click Undo — both return to the root and the new folder disappears
- [ ] Group into an *existing* folder name, click Undo — conversations return but that folder survives
- [ ] Search from the top bar — grid flattens, folder tiles disappear, matches from inside folders appear
- [ ] Clear search while inside a folder — returns to that folder
- [ ] A folder holding scratchpad pages shows "N · M notes"; opening it lists them under "ALSO IN THIS FOLDER" and Open jumps to that page
- [ ] Drag a tile into TextEdit — the transcript pastes, not a UUID
- [ ] Click a tile body — the detail sheet opens with Copy, Send, Delete working
- [ ] Group two conversations, then open Smart organize in classic view — a new conversation sharing that anchor tag is suggested for that folder

- [ ] **Step 6: Run the full core suite once more**

Run: `swift test --package-path MurmurCore`
Expected: PASS, 71 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add App/Sources/UI/MainWindowView.swift
git commit -m "feat(beta): add Beta toggle switching the main window to the springboard"
```

---

## Self-Review

**Spec coverage.** Every section of the design maps to a task: full-window takeover (10), anchor weights on NoteFolder (1, 4), renameable primary tag as `tags.first` (2, 8), always-group drop naming (3, 9), notes surfaced but not tiled (9), Smart organize anchor tier (5), beta toggle persistence (6, 10), search flattening (9), undo semantics including the reinforcement asymmetry (6), the migration guard (1), and the UTType fallback (7). The spec's `FolderDetailView.swift` became `FolderNotesSection.swift`; the deviation and its reason are recorded in the File Structure section.

**Type consistency.** `TileGrouping.Proposal` fields (`suggestedName`, `anchors`, `isConfident`) are used identically in Tasks 3, 4, and 6. `AppState.GroupingResult` (`folderID`, `shouldPromptForName`) is produced in Task 6 and consumed in Task 9. `createFolder(name:anchors:)` keeps its defaulted `anchors`, so the existing `SmartFolderOrganizer.apply` and `AppState.createFolder` call sites compile unchanged. `Theme.canvas` is added in Task 8 and consumed in Tasks 8 and 9.

**Test counts.** 39 baseline, +3 (Task 1) = 42, +7 (Task 2) = 49, +12 (Task 3) = 61, +6 (Task 4) = 67, +4 (Task 5) = 71.

## Risks carried from the spec

- **Notebook decode regression** is the only change that can destroy user data. Task 1 is ordered first and its migration test is the guard.
- **Custom UTType friction** — Task 7 Step 3 verifies the declaration landed in the built plist and documents the exact fallback if it did not.
- **Undo is not perfectly lossless** — reinforcement applied to a pre-existing folder is not rolled back. Deliberate; rolling it back would mean tracking per-drop deltas indefinitely.
