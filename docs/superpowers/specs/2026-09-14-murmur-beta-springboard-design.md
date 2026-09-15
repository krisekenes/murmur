# Murmur Beta Springboard — Design

**Date:** 2026-09-14
**Status:** Approved, pending implementation plan
**Applies to:** the development cycle after v0.2.0, behind a Beta toggle

## Summary

Add a toggleable **Beta view** to Murmur's main window: an iOS-springboard-style
grid of conversations. Tiles preview the saved conversation text instead of
showing an icon, each tile carries a renameable tag as its "filename", and
dragging one conversation onto another creates a folder whose shared tag is
persisted as a weighted **anchor**. Anchors give `SmartFolderOrganizer` a signal
that a human deliberately grouped these, which outranks its keyword guesses.

The beta view is a playground for UI experimentation. It writes to real data, so
every rule that mutates data lives in `MurmurCore` as pure, tested logic while the
view layer stays disposable.

## Goals

- A full-window springboard replacing the list feed when Beta is on.
- Conversation tiles that preview the transcript text.
- A renameable per-conversation "filename" that is a tag.
- Drag-to-group producing folders with weighted anchor tags.
- Manual groupings measurably outrank keyword guesses in Smart organize.
- Zero data loss for existing `history.json` and `notebook.json` files.

## Non-goals

- Replacing or removing the classic feed view. Beta is a toggle; classic remains
  the default and stays fully functional.
- Scratchpad pages as draggable grid tiles. Notes are surfaced but not
  manipulated from the springboard.
- UI test harness. This repo has none, and a playground does not justify adding one.
- Spring-loaded folders (hover-to-open during a drag). Deferred.

## Decisions

Each of these was chosen explicitly during brainstorming.

| Question | Decision |
|---|---|
| What does Beta take over? | The whole main window. Scratchpad moves behind a button. |
| Where does tag weight live? | On `NoteFolder`, as `anchorTags: [String: Double]`. |
| What is the tile "filename"? | The conversation's primary tag, renameable inline. |
| How is primary tag stored? | `tags.first`. Renaming reorders the existing array; no new field. |
| Drop with no shared tag? | Still groups. Names it `New Folder` and focuses the name field. |
| Do notes appear on the grid? | No, but folder tiles report true counts and list notes when opened. |

## Architecture

The beta UI is an isolated view tree. All decisions that mutate persisted data are
pure functions in `MurmurCore`.

### New files

```
App/Sources/UI/Beta/
  SpringboardView.swift      grid, drop targets, folder drill-in, search flattening
  ConversationTile.swift     text preview + renameable label
  FolderTile.swift           2x2 mini-preview, count sub-label
  FolderDetailView.swift     convo grid + "also in this folder" notes list

MurmurCore/Sources/MurmurCore/Stores/
  TileGrouping.swift         pure grouping and weighting decisions
```

`project.yml` declares `sources: [App/Sources, App/Resources]` as whole
directories, so new files require only `xcodegen generate` and no project-file
edits.

### Changed files

- `MurmurCore/Sources/MurmurCore/Stores/NotebookStore.swift` — `NoteFolder.anchorTags`, anchor seeding and reinforcement
- `MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift` — `setPrimaryTag`
- `MurmurCore/Sources/MurmurCore/Stores/SmartFolderOrganizer.swift` — anchor ranking tier
- `App/Sources/AppState.swift` — `betaMode`, grouping actions, grouping undo
- `App/Sources/UI/MainWindowView.swift` — Beta toggle in the top bar, branch on `betaMode`

## Data model

All changes are additive and backward-compatible. `HistoryEntry` and
`ScratchpadPage` are not modified.

### `NoteFolder.anchorTags`

```swift
public struct NoteFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var anchorTags: [String: Double] = [:]

    private enum CodingKeys: String, CodingKey { case id, name, anchorTags }

    public init(id: UUID, name: String, anchorTags: [String: Double] = [:]) {
        self.id = id; self.name = name; self.anchorTags = anchorTags
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        anchorTags = try values.decodeIfPresent([String: Double].self, forKey: .anchorTags) ?? [:]
    }
}
```

**The hand-written `init(from:)` is mandatory, not stylistic.** `NoteFolder`
currently uses synthesized `Codable`. `NotebookStore.init` decodes the entire
notebook with `try?`; on failure it copies the file aside as `.corrupt` and
replaces it with a single blank page. A required `anchorTags` key would make every
existing `notebook.json` fail to decode, silently destroying the user's visible
pages and folders. `decodeIfPresent` is the guard against that.

`anchorTags` keys are normalized through `NoteTagger.normalize`.

### Primary tag

The tile filename is `entry.tags.first`. Renaming reorders the array rather than
adding a field, so existing add/remove tag machinery, search, and filters keep
working unchanged.

```swift
// HistoryStore
public func setPrimaryTag(_ tag: String, for id: UUID)
```

Behavior: normalize the input; if empty, no-op. Remove any existing occurrence of
that tag, then insert at index 0. Idempotent.

### `TileGrouping`

```swift
public enum TileGrouping {
    public struct Proposal: Equatable {
        public let suggestedName: String      // e.g. "Interviews", or "New Folder"
        public let anchors: [String: Double]
        public let isConfident: Bool          // false => focus the name field on create
    }

    /// Decide the folder name and seed anchor weights for a two-conversation drop.
    public static func propose(_ a: [String], _ b: [String]) -> Proposal

    /// Fold a conversation's tags into a folder's existing anchor weights.
    public static func reinforced(_ existing: [String: Double], with tags: [String]) -> [String: Double]
}
```

Rules:

- **Shared tags exist** — the highest-scoring shared tag names the folder.
  `isConfident == true`. Shared tags seed at the shared weight; each
  conversation's non-shared tags seed at the co-occurring weight.
- **Multiple shared tags** — tie-break by `NoteTagger` ranking order, then
  alphabetically for full determinism.
- **No shared tags** — `suggestedName == "New Folder"`, `isConfident == false`.
  Both conversations' tags seed at the co-occurring weight.
- **Both untagged** — `suggestedName == "New Folder"`, `anchors` empty.
- Display names are title-cased the same way `SmartFolderOrganizer` already does
  it, reusing its `topicNames` map so `interview` becomes `Interviews` rather
  than `Interview`.
- `reinforced` is monotonic (weights never decrease) and bounded (weights
  converge rather than growing without limit).

The specific weight constants and the reinforcement curve are intentionally left
to the implementation step. They compound across every future grouping and
represent a judgment call about how aggressive Smart organize should become.

### Smart organize ranking

`SmartFolderOrganizer.suggestions` gains one tier ahead of name matching: if an
entry's tags intersect a folder's `anchorTags`, score by summed anchor weight.
A folder with empty `anchorTags` scores exactly as it does today, so v0.2.0
behavior is preserved for untouched folders. The existing ambiguity guard
(skip when the top two scores tie) still applies.

### Beta toggle

```swift
@Published public var betaMode: Bool = UserDefaults.standard.bool(forKey: "betaMode") {
    didSet { UserDefaults.standard.set(betaMode, forKey: "betaMode") }
}
```

Matches the `didSet` persistence pattern already used by `polishEnabled` and
`hotkey`. Defaults to off. Rendered as a labeled toggle in `MainWindowView`'s top
bar; `MainWindowView` branches its body on it.

## Interaction design

### Layout

`LazyVGrid(columns: [GridItem(.adaptive(minimum: 132))])`.

The **root grid** shows folder tiles plus **unfiled conversations only** -- a
conversation inside a folder appears in that folder, not at the root, exactly as
an app inside an iOS folder leaves the home screen. Opening a folder shows that
folder's conversations.

Within any grid, folders sort first and alphabetically by name, then
conversations newest-first by `createdAt`.

```
CONVERSATION TILE            FOLDER TILE
+-------------+              +-------------+
| so I need   |              | [ ] [ ]     |   2x2 mini-previews
| to follow   |              |             |   of the 4 newest
| up with the |              | [ ] [ ]     |   convos inside
| recruiter.  |  fades out   |             |
+-------------+              +-------------+
   #interview                  Interviews
   (or "9:42 PM")              12 / 3 notes
```

Conversation preview text is `entry.polished`, falling back to `entry.raw` when
polished is empty. The label is `tags.first`, falling back to a short time stamp
when the conversation has no tags.

Folder tiles show the conversation count, then a middle dot (U+00B7), then
the note count, e.g. `12 · 3 notes`. The note segment is omitted entirely when
the folder holds no notes. Counts include both
`HistoryEntry` and `ScratchpadPage` rows pointing at that folder, because
`NoteFolder` is a single shared namespace across both.

### Drag and drop

Payload is a `Transferable` struct carrying both the id and the text:

```swift
struct ConversationRef: Codable, Transferable {
    let id: UUID
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .murmurConversation)
        ProxyRepresentation(exporting: \.text)
    }
}
```

The `CodableRepresentation` serves in-app drops; the `ProxyRepresentation` means
dragging a tile into TextEdit or Slack pastes the transcript rather than a UUID.
The custom UTType is declared via `UTExportedTypeDeclarations` in `project.yml`'s
`info.properties`.

**Fallback:** if the exported UTType proves unreliable, use
`.draggable(entry.id.uuidString)` with `.dropDestination(for: String.self)` and
drop out-of-app dragging from scope. In-app behavior is identical either way.

| Drop | Result |
|---|---|
| convo onto convo | Create folder from `TileGrouping.propose`; move both in; focus name field when `isConfident == false` |
| convo onto folder tile | Move in; update anchors via `reinforced(folder.anchorTags, with: entry.tags)` |
| convo onto grid background, inside a folder | Unfile (set `folderID` to nil) |
| convo onto the "All" breadcrumb | Unfile |
| convo onto itself | No-op, tile springs back |
| convo onto the folder it already occupies | No-op, tile springs back |

Folder name collisions merge rather than duplicate: `NotebookStore.createFolder`
already returns the existing folder on a case-insensitive name match. Grouping two
conversations under a name that already exists joins that folder and reinforces
its anchors. This behavior is load-bearing and must be preserved.

### Renaming

Tile body and tile label are separate hit targets, so there is no click
ambiguity: the body opens the item, the label begins a rename.

- Return or focus loss commits. Escape reverts. Empty input reverts.
- Conversation labels commit through `HistoryStore.setPrimaryTag`.
- Folder labels commit through the existing `NotebookStore.renameFolder`, which
  already rejects case-insensitive duplicates; a rejected rename reverts.

### Undo

Session-scoped, mirroring the existing `lastOrganization` pattern in `AppState`.

```swift
private var lastGrouping: (folderID: UUID, movedIDs: [UUID], folderWasCreated: Bool)?
public func undoLastGrouping()
```

A bar appears after a grouping reading `Grouped 2 into Interviews`, followed by
a middle dot (U+00B7) and an `Undo` button.
Undo unfiles only entries **still in that folder**, using the same defensive guard
as `undoOrganization`, so a manual move made afterward survives. The folder is
deleted only if this action created it and it now holds neither conversations nor
notes. Anchor weights seeded by the undone grouping are removed with the folder;
weights added by reinforcement to a pre-existing folder are not rolled back.

### Search

Reuses the existing top-bar search binding. When search is non-empty the grid
flattens: matching conversations from every folder are shown and folder tiles are
hidden, Finder-style. Clearing search restores the folder the user was in.

### Scratchpad access

A button at the bottom-right of the springboard opens the existing
`ScratchpadView` in a sheet. The scratchpad itself is unchanged.

## Error handling and edge cases

| Case | Behavior |
|---|---|
| Both conversations untagged | Folder named `New Folder`, no anchors seeded |
| Entry deleted mid-drag | Store methods guard on `firstIndex(where:)` and no-op |
| Folder deleted while open | Pop to the root grid |
| Empty grid | Reuse the feed's existing empty-state copy |
| `polished` empty | Preview falls back to `raw` |
| Rename to a duplicate folder name | Rejected by `renameFolder`; label reverts |
| Notebook file unreadable | Existing `NotebookStore` corrupt-file path is unchanged |
| Legacy `notebook.json` without `anchorTags` | Decodes intact via `decodeIfPresent`; anchors default to empty |

## Testing

New XCTest files alongside the existing 39 tests. `swift test --package-path MurmurCore`.

**`TileGroupingTests`**
- Single shared tag names the folder and sets `isConfident == true`
- Multiple shared tags tie-break deterministically by `NoteTagger` ranking, then alphabetically
- Zero shared tags yields `New Folder`, `isConfident == false`, both tag sets seeded as co-occurring
- Both untagged yields `New Folder` with empty anchors
- Topic display names match `SmartFolderOrganizer` output (`interview` to `Interviews`)
- `reinforced` is monotonic and bounded across repeated application

**`NoteFolderMigrationTests`**
- A v0.2.0 `notebook.json` containing folders without an `anchorTags` key decodes
  with all folders and pages intact, and does not trip the corrupt-file path.
  This is the data-loss guard and is the highest-priority test in the set.
- A notebook written with anchors round-trips them

**`HistoryStoreTests` additions**
- `setPrimaryTag` moves an existing tag to index 0 without duplicating it
- `setPrimaryTag` inserts an unknown tag at index 0
- Input is normalized through `NoteTagger.normalize`
- Empty or whitespace-only input is a no-op
- Applying the same primary tag twice is idempotent

**`SmartFolderOrganizerTests` additions**
- A folder with matching anchors outranks a folder matching only by name
- A folder with empty `anchorTags` produces exactly today's suggestions
- Tied anchor scores still hit the existing ambiguity guard and stay unfiled

**Manual verification** covers the UI: toggle in and out of Beta, group two
tagged conversations, group two untagged conversations, drop into an existing
folder, drag out to unfile, rename a conversation label, rename a folder label,
undo a grouping, search while inside a folder, and confirm folder note counts
against the scratchpad browser.

## Risks

- **Notebook decode regression.** Mitigated by the hand-written `init(from:)` and
  `NoteFolderMigrationTests`. This is the only change in the design that can
  destroy existing user data.
- **Custom UTType friction.** Mitigated by the documented string-payload fallback,
  which costs only out-of-app dragging.
- **Anchor weights drifting toward over-confident suggestions.** Mitigated by
  bounded reinforcement and by `SmartFolderOrganizer` remaining preview-and-apply
  rather than automatic.
- **Beta and classic views diverging.** Accepted. Beta is explicitly a playground
  and classic remains the default.

## Open implementation decision

`TileGrouping.propose`'s weight constants and `reinforced`'s curve are left for
the implementation step rather than fixed here. They determine how aggressively
manual groupings steer future auto-filing, compound over time, and are a product
judgment rather than an architectural one. The signature, the rules above, and
the tests constrain the shape; the numbers are chosen when the function is written.
