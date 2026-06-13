# Murmur Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free, fully-local macOS menu-bar dictation app — hold a key, speak, and polished text lands in the focused app, with nothing leaving the machine.

**Architecture:** Two-layer split. `MurmurCore` is a pure-logic SwiftPM package (state machine, stores, prompt builder, paste-guard) with no heavy dependencies, unit-tested fast via `swift test`. The `Murmur` Xcode app target wires the system integration (CGEventTap hotkeys, AVAudioEngine capture, FluidAudio ASR, mlx-swift-lm polish, AppKit/SwiftUI surfaces) on top of `MurmurCore`. The Xcode project is generated from a text `project.yml` via XcodeGen so it stays diff-friendly in git.

**Tech Stack:** Swift 6, SwiftUI + AppKit, FluidAudio 0.15.2 (Parakeet v2 ASR on CoreML/ANE), mlx-swift-lm 3.31.3 (Qwen3.5-2B-4bit polish), CoreGraphics event taps, XcodeGen.

---

## Prerequisites (one-time, before Task 1)

These are environment setup, not code. Run them once and confirm:

- [ ] **Install XcodeGen:** `brew install xcodegen` → verify `xcodegen --version`
- [ ] **Install the Metal toolchain** (MLX compiles Metal shaders; without this the app builds but crashes at first MLX eval with "Failed to load the default metallib"):
  `xcodebuild -downloadComponent MetalToolchain` → verify `xcodebuild -showComponent MetalToolchain` shows `Status: installed`
- [ ] Confirm `swift --version` is 6.x and `xcodebuild -version` is Xcode 26.x

---

## Shared Types Reference

These types are defined once (in the tasks noted) and referenced throughout. Keep names exact.

```swift
// Task 2 — MurmurCore/Sources/MurmurCore/Hotkey/DictationStateMachine.swift
public enum HotkeyMode: Equatable, Sendable { case hold, locked }
public enum HotkeyEvent: Equatable, Sendable { case keyDown, keyUp, escape, timeout }
public enum DictationEffect: Equatable, Sendable {
    case startRecording          // begin capturing audio
    case finishRecording         // stop + run the transcribe→polish→insert pipeline
    case cancelRecording         // discard buffer, insert nothing
    case scheduleTimeout(after: TimeInterval)  // controller arms a one-shot timer that feeds .timeout
    case none
}

// Task 5 — pipeline result the controller persists
// Task 4 — HistoryEntry: id, raw, polished, createdAt, appName
// Task 6 — PasteDecision: pure should-restore logic
```

Tunable constants (Task 2, `DictationTuning`):
```swift
public struct DictationTuning: Sendable {
    public var tapMaxDuration: TimeInterval = 0.25   // a press shorter than this is a "tap", not a hold
    public var doubleTapWindow: TimeInterval = 0.30  // second tap must begin within this of the first tap's release
    public var minPolishWords: Int = 4               // skip the LLM polish below this word count
    public init() {}
}
```

---

## Task 1: Project skeleton

**Files:**
- Create: `MurmurCore/Package.swift`
- Create: `MurmurCore/Sources/MurmurCore/MurmurCore.swift`
- Create: `MurmurCore/Tests/MurmurCoreTests/SmokeTests.swift`
- Create: `project.yml`
- Create: `App/Info.plist`
- Create: `App/Murmur.entitlements`
- Create: `App/Sources/MurmurApp.swift`
- Create: `.gitignore`

- [ ] **Step 1: Create the MurmurCore package manifest**

`MurmurCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MurmurCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MurmurCore", targets: ["MurmurCore"])],
    targets: [
        .target(name: "MurmurCore"),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
    ]
)
```

- [ ] **Step 2: Add a placeholder source + smoke test**

`MurmurCore/Sources/MurmurCore/MurmurCore.swift`:
```swift
public enum MurmurCore {
    public static let version = "0.1.0"
}
```

`MurmurCore/Tests/MurmurCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import MurmurCore

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(MurmurCore.version, "0.1.0")
    }
}
```

- [ ] **Step 3: Run the smoke test**

Run: `cd MurmurCore && swift test`
Expected: PASS, 1 test.

- [ ] **Step 4: Write the XcodeGen project spec**

`project.yml`:
```yaml
name: Murmur
options:
  bundleIdPrefix: com.murmur
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""           # set if you have one; ad-hoc signing is fine for local use
    CODE_SIGN_STYLE: Automatic
packages:
  MurmurCore:
    path: MurmurCore
  FluidAudio:
    url: https://github.com/FluidInference/FluidAudio.git
    exactVersion: 0.15.2
  mlx-swift-lm:
    url: https://github.com/ml-explore/mlx-swift-lm
    minVersion: 3.31.3
    maxVersion: 4.0.0
  swift-huggingface:
    url: https://github.com/huggingface/swift-huggingface
    minVersion: 0.9.0
    maxVersion: 1.0.0
  swift-transformers:
    url: https://github.com/huggingface/swift-transformers
    minVersion: 1.3.0
    maxVersion: 2.0.0
targets:
  Murmur:
    type: application
    platform: macOS
    sources: [App/Sources]
    info:
      path: App/Info.plist
      properties:
        LSUIElement: true
        NSMicrophoneUsageDescription: "Murmur transcribes your speech locally. Audio never leaves your Mac."
        CFBundleDisplayName: Murmur
    entitlements:
      path: App/Murmur.entitlements
      properties:
        com.apple.security.device.audio-input: true
    dependencies:
      - package: MurmurCore
      - package: FluidAudio
        product: FluidAudio
      - package: mlx-swift-lm
        product: MLXLLM
      - package: mlx-swift-lm
        product: MLXLMCommon
      - package: mlx-swift-lm
        product: MLXHuggingFace
      - package: swift-huggingface
        product: HuggingFace
      - package: swift-transformers
        product: Tokenizers
```
> Note: do **not** add the `MLXVLM` product — its factory resolves the Qwen3.5 checkpoint down the vision path. `MLXLLM` alone loads it text-only.

- [ ] **Step 5: Add Info.plist, entitlements, a minimal app entry, and .gitignore**

`App/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
```
(XcodeGen merges the `info.properties` above into this.)

`App/Murmur.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
```
> Note: do **not** enable App Sandbox for v1 — the CGEventTap-based global hotkey and synthetic-paste injection need an un-sandboxed binary. Revisit if distributing via the App Store (out of scope).

`App/Sources/MurmurApp.swift`:
```swift
import SwiftUI

@main
struct MurmurApp: App {
    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: "waveform") {
            Text("Murmur \(MurmurCoreVersionShim.version)")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

// Proves the MurmurCore link works; removed once real menu lands in Task 12.
import MurmurCore
enum MurmurCoreVersionShim { static let version = MurmurCore.version }
```

`.gitignore`:
```
.build/
DerivedData/
Murmur.xcodeproj/
*.xcuserstate
.DS_Store
```

- [ ] **Step 6: Generate and build the app**

Run: `xcodegen generate && xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. (First run resolves SwiftPM packages; may take several minutes.)

- [ ] **Step 7: Commit**

```bash
git add MurmurCore project.yml App .gitignore
git commit -m "chore(murmur): scaffold MurmurCore package + XcodeGen app target"
```

---

## Task 2: Dictation state machine (the hotkey brain)

This is pure logic — no CGEventTap, no timers, fully deterministic. Every event carries a timestamp; the controller (Task 7) translates real key events and a real timer into these calls.

**Files:**
- Create: `MurmurCore/Sources/MurmurCore/Hotkey/DictationStateMachine.swift`
- Test: `MurmurCore/Tests/MurmurCoreTests/DictationStateMachineTests.swift`

- [ ] **Step 1: Write the failing tests**

`MurmurCore/Tests/MurmurCoreTests/DictationStateMachineTests.swift`:
```swift
import XCTest
@testable import MurmurCore

final class DictationStateMachineTests: XCTestCase {
    private func machine() -> DictationStateMachine { DictationStateMachine(tuning: DictationTuning()) }

    func test_holdThenRelease_transcribes() {
        let m = machine()
        XCTAssertEqual(m.handle(.keyDown, at: 0.0), .startRecording)
        // held 0.5s (> tapMaxDuration) => normal push-to-talk
        XCTAssertEqual(m.handle(.keyUp, at: 0.5), .finishRecording)
        XCTAssertEqual(m.state, .idle)
    }

    func test_escapeWhileHolding_cancels() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        XCTAssertEqual(m.handle(.escape, at: 0.2), .cancelRecording)
        XCTAssertEqual(m.state, .idle)
    }

    func test_quickTap_armsDoubleTapWindowAndDiscards() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        // released after 0.1s (< tapMaxDuration) => a tap; discard and open the double-tap window
        XCTAssertEqual(m.handle(.keyUp, at: 0.1), .cancelRecording)
        XCTAssertEqual(m.pendingTimeout, 0.30)   // controller arms a one-shot timer off this
    }

    func test_doubleTap_entersLockedRecording_andTapStops() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)                 // first tap (discard + schedule timeout)
        XCTAssertEqual(m.handle(.keyDown, at: 0.25), .startRecording) // second tap within window => lock
        XCTAssertEqual(m.handle(.keyUp, at: 0.30), .none)            // ignore the arming tap's release
        XCTAssertEqual(m.state, .recording(.locked))
        XCTAssertEqual(m.handle(.keyDown, at: 5.0), .finishRecording) // a later tap stops + transcribes
        XCTAssertEqual(m.state, .idle)
    }

    func test_singleTapTimesOut_toIdle_noEffect() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        // no second tap arrives; timer fires after the window
        XCTAssertEqual(m.handle(.timeout, at: 0.45), DictationEffect.none)
        XCTAssertEqual(m.state, .idle)
    }

    func test_secondTapAfterWindow_isTreatedAsFreshHold() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        _ = m.handle(.timeout, at: 0.45)             // window already closed -> idle
        XCTAssertEqual(m.handle(.keyDown, at: 0.50), .startRecording) // new independent hold
        XCTAssertEqual(m.state, .recording(.hold))
    }

    func test_escapeWhileLocked_cancels() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        _ = m.handle(.keyDown, at: 0.25)
        _ = m.handle(.keyUp, at: 0.30)
        XCTAssertEqual(m.handle(.escape, at: 1.0), .cancelRecording)
        XCTAssertEqual(m.state, .idle)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd MurmurCore && swift test --filter DictationStateMachineTests`
Expected: FAIL (type `DictationStateMachine` not found).

- [ ] **Step 3: Implement the state machine**

`MurmurCore/Sources/MurmurCore/Hotkey/DictationStateMachine.swift`:
```swift
import Foundation

public enum HotkeyMode: Equatable, Sendable { case hold, locked }
public enum HotkeyEvent: Equatable, Sendable { case keyDown, keyUp, escape, timeout }

public enum DictationEffect: Equatable, Sendable {
    case startRecording
    case finishRecording
    case cancelRecording
    case scheduleTimeout(after: TimeInterval)
    case none
}

public struct DictationTuning: Sendable {
    public var tapMaxDuration: TimeInterval = 0.25
    public var doubleTapWindow: TimeInterval = 0.30
    public var minPolishWords: Int = 4
    public init() {}
}

public final class DictationStateMachine {
    public enum State: Equatable, Sendable {
        case idle
        case recording(HotkeyMode)
        case awaitingSecondTap      // first quick tap released, waiting for a partner
        case lockedArmed            // second tap's key down; recording, ignore its release
    }

    public private(set) var state: State = .idle

    private let tuning: DictationTuning
    private var keyDownAt: TimeInterval = 0
    private var firstTapReleasedAt: TimeInterval = 0

    public init(tuning: DictationTuning = DictationTuning()) { self.tuning = tuning }

    @discardableResult
    public func handle(_ event: HotkeyEvent, at now: TimeInterval) -> DictationEffect {
        transition(event, now)
    }

    private func transition(_ event: HotkeyEvent, _ now: TimeInterval) -> DictationEffect {
        switch (state, event) {
        case (.idle, .keyDown):
            keyDownAt = now
            state = .recording(.hold)
            return .startRecording

        case (.recording(.hold), .keyUp):
            let heldFor = now - keyDownAt
            if heldFor >= tuning.tapMaxDuration {
                state = .idle
                return .finishRecording            // normal push-to-talk
            }
            firstTapReleasedAt = now
            state = .awaitingSecondTap
            return .cancelRecording                // discard the tap; controller arms a timer off `pendingTimeout`

        case (.recording(.hold), .escape):
            state = .idle
            return .cancelRecording

        case (.awaitingSecondTap, .keyDown):
            if now - firstTapReleasedAt <= tuning.doubleTapWindow {
                state = .lockedArmed
                return .startRecording
            }
            // partner arrived too late: treat as a brand-new hold
            keyDownAt = now
            state = .recording(.hold)
            return .startRecording

        case (.awaitingSecondTap, .timeout), (.awaitingSecondTap, .escape):
            state = .idle
            return .none

        case (.lockedArmed, .keyUp):
            state = .recording(.locked)
            return .none                           // ignore the arming tap's release

        case (.lockedArmed, .escape):
            state = .idle
            return .cancelRecording

        case (.recording(.locked), .keyDown):
            state = .idle
            return .finishRecording

        case (.recording(.locked), .escape):
            state = .idle
            return .cancelRecording

        default:
            return .none
        }
    }
}
```

> **Double-tap timeout wiring:** the `.cancelRecording` returned on a quick tap must be paired with a scheduled timeout so the controller can fire `.timeout` after `doubleTapWindow`. Rather than returning two effects, the machine exposes the window via `pendingTimeout` and the controller (Task 7) arms a one-shot timer whenever it is non-nil. Add this helper (the `test_quickTap_armsDoubleTapWindowAndDiscards` test already asserts against it):

```swift
extension DictationStateMachine {
    /// If a double-tap window just opened, returns the delay to arm a one-shot
    /// timer that will feed `.timeout` back into `handle(_:at:)`.
    public var pendingTimeout: TimeInterval? {
        state == .awaitingSecondTap ? tuning.doubleTapWindow : nil
    }
}
```
(The `.scheduleTimeout` effect case stays in the enum as the documented contract, but the machine signals timing through `pendingTimeout` rather than returning it — simpler for the controller and fully testable.)

- [ ] **Step 4: Run to verify pass**

Run: `cd MurmurCore && swift test --filter DictationStateMachineTests`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Hotkey MurmurCore/Tests/MurmurCoreTests/DictationStateMachineTests.swift
git commit -m "feat(core): dictation hotkey state machine with hold + double-tap-lock"
```

---

## Task 3: Vocabulary store

**Files:**
- Create: `MurmurCore/Sources/MurmurCore/Stores/VocabularyStore.swift`
- Test: `MurmurCore/Tests/MurmurCoreTests/VocabularyStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`MurmurCore/Tests/MurmurCoreTests/VocabularyStoreTests.swift`:
```swift
import XCTest
@testable import MurmurCore

final class VocabularyStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vocab-\(UUID()).json")
    }

    func test_addPersistsAndDeduplicatesCaseInsensitively() throws {
        let url = tempURL()
        let store = try VocabularyStore(fileURL: url)
        store.add("Kristoffer")
        store.add("kristoffer")            // duplicate, case-insensitive
        store.add("Mossflower")
        XCTAssertEqual(store.words, ["Kristoffer", "Mossflower"])

        let reloaded = try VocabularyStore(fileURL: url)
        XCTAssertEqual(reloaded.words, ["Kristoffer", "Mossflower"])
    }

    func test_removeDeletesAndPersists() throws {
        let url = tempURL()
        let store = try VocabularyStore(fileURL: url)
        store.add("Alpha"); store.add("Beta")
        store.remove("Alpha")
        XCTAssertEqual(store.words, ["Beta"])
        XCTAssertEqual(try VocabularyStore(fileURL: url).words, ["Beta"])
    }

    func test_blankInputIsIgnored() throws {
        let store = try VocabularyStore(fileURL: tempURL())
        store.add("   ")
        XCTAssertTrue(store.words.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd MurmurCore && swift test --filter VocabularyStoreTests`
Expected: FAIL (`VocabularyStore` not found).

- [ ] **Step 3: Implement**

`MurmurCore/Sources/MurmurCore/Stores/VocabularyStore.swift`:
```swift
import Foundation

public final class VocabularyStore {
    public private(set) var words: [String] = []
    private let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            words = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
    }

    public func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        words.append(trimmed)
        persist()
    }

    public func remove(_ word: String) {
        words.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(words) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd MurmurCore && swift test --filter VocabularyStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/VocabularyStore.swift MurmurCore/Tests/MurmurCoreTests/VocabularyStoreTests.swift
git commit -m "feat(core): vocabulary store with case-insensitive dedupe + persistence"
```

---

## Task 4: History store

**Files:**
- Create: `MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift`
- Test: `MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift`:
```swift
import XCTest
@testable import MurmurCore

final class HistoryStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
    }

    private func entry(_ text: String, at t: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), raw: text, polished: text, createdAt: Date(timeIntervalSince1970: t), appName: "TextEdit")
    }

    func test_appendStoresNewestFirstAndPersists() throws {
        let url = tempURL()
        let store = try HistoryStore(fileURL: url, limit: 200)
        store.append(entry("first", at: 1))
        store.append(entry("second", at: 2))
        XCTAssertEqual(store.entries.map(\.raw), ["second", "first"])
        XCTAssertEqual(try HistoryStore(fileURL: url, limit: 200).entries.map(\.raw), ["second", "first"])
    }

    func test_capDropsOldest() throws {
        let store = try HistoryStore(fileURL: tempURL(), limit: 3)
        for i in 1...5 { store.append(entry("e\(i)", at: TimeInterval(i))) }
        XCTAssertEqual(store.entries.map(\.raw), ["e5", "e4", "e3"])
    }

    func test_deleteRemovesById() throws {
        let store = try HistoryStore(fileURL: tempURL(), limit: 200)
        let e = entry("keep", at: 1)
        store.append(entry("drop", at: 2))
        store.append(e)
        store.delete(id: store.entries[0].id)          // delete "keep" (newest)
        XCTAssertEqual(store.entries.map(\.raw), ["drop"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd MurmurCore && swift test --filter HistoryStoreTests`
Expected: FAIL (`HistoryEntry`/`HistoryStore` not found).

- [ ] **Step 3: Implement**

`MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift`:
```swift
import Foundation

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let raw: String
    public let polished: String
    public let createdAt: Date
    public let appName: String

    public init(id: UUID, raw: String, polished: String, createdAt: Date, appName: String) {
        self.id = id; self.raw = raw; self.polished = polished
        self.createdAt = createdAt; self.appName = appName
    }
}

public final class HistoryStore {
    public private(set) var entries: [HistoryEntry] = []   // newest first
    private let fileURL: URL
    private let limit: Int

    public init(fileURL: URL, limit: Int = 200) throws {
        self.fileURL = fileURL
        self.limit = limit
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    public func append(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        persist()
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd MurmurCore && swift test --filter HistoryStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Stores/HistoryStore.swift MurmurCore/Tests/MurmurCoreTests/HistoryStoreTests.swift
git commit -m "feat(core): history store with newest-first ordering, cap, and delete"
```

---

## Task 5: Polish prompt builder + skip rule

**Files:**
- Create: `MurmurCore/Sources/MurmurCore/Polish/PolishPromptBuilder.swift`
- Test: `MurmurCore/Tests/MurmurCoreTests/PolishPromptBuilderTests.swift`

- [ ] **Step 1: Write the failing tests**

`MurmurCore/Tests/MurmurCoreTests/PolishPromptBuilderTests.swift`:
```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd MurmurCore && swift test --filter PolishPromptBuilderTests`
Expected: FAIL (`PolishPromptBuilder` not found).

- [ ] **Step 3: Implement**

`MurmurCore/Sources/MurmurCore/Polish/PolishPromptBuilder.swift`:
```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `cd MurmurCore && swift test --filter PolishPromptBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Polish MurmurCore/Tests/MurmurCoreTests/PolishPromptBuilderTests.swift
git commit -m "feat(core): polish prompt builder with vocabulary injection + skip rule"
```

---

## Task 6: Paste-restore decision (pasteboard ownership guard)

The risky part of synthetic paste is restoring the user's clipboard without clobbering something they copied in the meantime. The decision is pure logic: after we write our text, we record the pasteboard's `changeCount`. Later we only restore if the count is unchanged (nobody else wrote to it).

**Files:**
- Create: `MurmurCore/Sources/MurmurCore/Paste/PasteDecision.swift`
- Test: `MurmurCore/Tests/MurmurCoreTests/PasteDecisionTests.swift`

- [ ] **Step 1: Write the failing tests**

`MurmurCore/Tests/MurmurCoreTests/PasteDecisionTests.swift`:
```swift
import XCTest
@testable import MurmurCore

final class PasteDecisionTests: XCTestCase {
    func test_restoresWhenWeStillOwnPasteboard() {
        // we wrote our text; pasteboard moved to changeCount 42 and is unchanged since
        let d = PasteDecision(ownedChangeCount: 42)
        XCTAssertTrue(d.shouldRestore(currentChangeCount: 42))
    }

    func test_skipsRestoreWhenSomeoneElseCopied() {
        let d = PasteDecision(ownedChangeCount: 42)
        XCTAssertFalse(d.shouldRestore(currentChangeCount: 43))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd MurmurCore && swift test --filter PasteDecisionTests`
Expected: FAIL (`PasteDecision` not found).

- [ ] **Step 3: Implement**

`MurmurCore/Sources/MurmurCore/Paste/PasteDecision.swift`:
```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `cd MurmurCore && swift test --filter PasteDecisionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MurmurCore/Sources/MurmurCore/Paste MurmurCore/Tests/MurmurCoreTests/PasteDecisionTests.swift
git commit -m "feat(core): pasteboard ownership guard for safe clipboard restore"
```

**End of Phase 1.** At this point `swift test` runs the full pure-logic suite fast (no models, no Metal). Everything below lives in the `Murmur` app target and builds/tests via `xcodebuild`.

---

## Task 7: HotkeyMonitor (CGEventTap → state machine)

Wraps a global CGEventTap, detects Fn (or Right-Option) press/release, drives `DictationStateMachine`, and emits effects to a delegate. Hard to unit-test (needs a real event tap + permissions); verified manually. Implements the Hex-derived patterns: `.maskSecondaryFn` for Fn, separate Fn-state tracking, and a watchdog that re-enables a tap disabled by timeout.

**Files:**
- Create: `App/Sources/System/HotkeyMonitor.swift`

- [ ] **Step 1: Implement HotkeyMonitor**

`App/Sources/System/HotkeyMonitor.swift`:
```swift
import AppKit
import CoreGraphics
import MurmurCore

@MainActor
public protocol HotkeyMonitorDelegate: AnyObject {
    func hotkeyDidEmit(_ effect: DictationEffect)
}

public enum HotkeyChoice: String, CaseIterable, Sendable {
    case fn          // the Globe/Fn key
    case rightOption
}

/// All mutable state is touched only from the main run loop: `start()` is called
/// on the main actor, so the tap's run-loop source and its callback both run on
/// the main thread. Marked `@unchecked Sendable` so the C callback trampoline can
/// hold an `Unmanaged` pointer to it under Swift 6 strict concurrency.
public final class HotkeyMonitor: @unchecked Sendable {
    public weak var delegate: HotkeyMonitorDelegate?

    private let machine: DictationStateMachine
    private let choice: HotkeyChoice
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyDown = false
    private var doubleTapTimer: Timer?
    private var watchdog: Timer?

    public init(choice: HotkeyChoice, machine: DictationStateMachine = DictationStateMachine()) {
        self.choice = choice
        self.machine = machine
    }

    public func start() {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap else {
            NSLog("Murmur: failed to create event tap — check Accessibility + Input Monitoring permissions")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        startWatchdog()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime

        // Esc anywhere cancels.
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            emit(machine.handle(.escape, at: now)); return
        }

        switch choice {
        case .fn:
            guard type == .flagsChanged else { return }
            let down = event.flags.contains(.maskSecondaryFn)
            guard down != isHotkeyDown else { return }   // dedupe; Fn flag bleeds into other keys
            isHotkeyDown = down
            emit(machine.handle(down ? .keyDown : .keyUp, at: now))
        case .rightOption:
            guard type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == 61 else { return } // kVK_RightOption
            let down = event.flags.contains(.maskAlternate)
            guard down != isHotkeyDown else { return }
            isHotkeyDown = down
            emit(machine.handle(down ? .keyDown : .keyUp, at: now))
        }
    }

    private func emit(_ effect: DictationEffect) {
        // Arm the double-tap timer when a window opens.
        doubleTapTimer?.invalidate()
        if let delay = machine.pendingTimeout {
            doubleTapTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.emit(self.machine.handle(.timeout, at: ProcessInfo.processInfo.systemUptime))
            }
        }
        guard effect != .none else { return }
        Task { @MainActor in self.delegate?.hotkeyDidEmit(effect) }  // statically main-isolated; satisfies @MainActor delegate
    }

    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual verification** (record result in the task)

Wire a temporary `print` delegate in `MurmurApp` (or defer to Task 17). Grant Accessibility + Input Monitoring when prompted. Verify console prints `startRecording` on Fn-down and `finishRecording` on a >0.25s Fn-hold release; `startRecording`→locked on a double-tap. Note: macOS reserves Fn — set System Settings → Keyboard → "Press 🌐 to" → "Do Nothing" first.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/System/HotkeyMonitor.swift
git commit -m "feat(app): global hotkey monitor (Fn / Right-Option) driving the state machine"
```

---

## Task 8: AudioRecorder

Captures mic audio via AVAudioEngine, converts each buffer to 16 kHz mono Float32 with FluidAudio's `AudioConverter`, and accumulates samples in memory (never to disk).

**Files:**
- Create: `App/Sources/System/AudioRecorder.swift`

- [ ] **Step 1: Implement**

`App/Sources/System/AudioRecorder.swift`:
```swift
import AVFoundation
import FluidAudio

public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let converter = AudioConverter()    // default target: 16kHz mono Float32
    private var samples: [Float] = []
    private var isRunning = false

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if let converted = try? self.converter.resampleBuffer(buffer) {
                self.samples.append(contentsOf: converted)
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stops capture and returns the accumulated 16kHz mono samples.
    @discardableResult
    public func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        return samples
    }

    /// Discards in-flight audio (cancel path).
    public func cancel() {
        _ = stop()
        samples.removeAll(keepingCapacity: false)
    }

    /// Most recent input amplitude (0...1) for the overlay meter.
    public var currentLevel: Float {
        guard let last = samples.suffix(1024).max(by: { abs($0) < abs($1) }) else { return 0 }
        return min(1, abs(last))
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/Sources/System/AudioRecorder.swift
git commit -m "feat(app): in-memory mic recorder with FluidAudio 16kHz conversion"
```

---

## Task 9: TranscriptionEngine (FluidAudio Parakeet v2)

Loads the English Parakeet model once at launch and transcribes a sample buffer. Uses the verified v0.15.2 API: `AsrModels.downloadAndLoad(version: .v2)` → `AsrManager.loadModels(_:)` → per-utterance `TdtDecoderState.make(...)` → `transcribe(_:decoderState:)`.

**Files:**
- Create: `App/Sources/System/TranscriptionEngine.swift`

- [ ] **Step 1: Implement**

`App/Sources/System/TranscriptionEngine.swift`:
```swift
import Foundation
import FluidAudio

public actor TranscriptionEngine {
    public enum LoadState: Sendable { case unloaded, loading, ready, failed(String) }
    public private(set) var loadState: LoadState = .unloaded

    private var manager: AsrManager?

    public init() {}

    /// Call once at launch (cold CoreML compile happens here, ~3s).
    public func load(progress: (@Sendable (Double) -> Void)? = nil) async {
        loadState = .loading
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v2) { p in progress?(p) }
            let mgr = AsrManager(config: .default)
            try await mgr.loadModels(models)
            manager = mgr
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Transcribe one utterance. Fresh decoder state per call.
    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw TranscriptionError.notReady }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)
        return result.text
    }

    public enum TranscriptionError: Error { case notReady }
}
```

> If `decoderLayerCount` or `TdtDecoderState.make` differ in the pinned tag, check `AsrManager` / `TdtDecoderState` in `~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/FluidAudio/` — the research verified these against tag 0.15.2, but the SDK moves fast, hence the exact pin.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/Sources/System/TranscriptionEngine.swift
git commit -m "feat(app): Parakeet v2 transcription engine via FluidAudio"
```

---

## Task 10: PolishEngine (mlx-swift-lm Qwen3.5-2B-4bit)

Loads the small LLM once, polishes a transcript with a 3-second timeout, and falls back to the raw transcript on timeout or error. Honors a user toggle and the word-count skip rule (via `PolishPromptBuilder` from Task 5).

**Files:**
- Create: `App/Sources/System/PolishEngine.swift`

- [ ] **Step 1: Implement**

`App/Sources/System/PolishEngine.swift`:
```swift
import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import MurmurCore

public actor PolishEngine {
    public enum LoadState: Sendable { case unloaded, loading, ready, failed(String) }
    public private(set) var loadState: LoadState = .unloaded

    private var container: ModelContainer?
    private let builder: PolishPromptBuilder
    private let timeout: TimeInterval

    public init(minWords: Int, timeout: TimeInterval = 3.0) {
        self.builder = PolishPromptBuilder(minWords: minWords)
        self.timeout = timeout
    }

    public func load(progress: (@Sendable (Double) -> Void)? = nil) async {
        loadState = .loading
        do {
            let c = try await #huggingFaceLoadModelContainer(
                configuration: ModelConfiguration(id: "mlx-community/Qwen3.5-2B-4bit")
            ) { p in progress?(p.fractionCompleted) }
            container = c
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Returns polished text, or the raw transcript unchanged if polishing is
    /// skipped (too short), disabled, times out, or errors. Never throws.
    public func polish(_ raw: String, vocabulary: [String], enabled: Bool) async -> String {
        guard enabled, builder.shouldPolish(raw), let container, case .ready = loadState else {
            return raw
        }
        let system = builder.systemPrompt(vocabulary: vocabulary)
        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.3),
            additionalContext: ["enable_thinking": false]   // keep latency low
        )
        return await withTimeoutOrRaw(raw: raw) {
            (try? await session.respond(to: raw))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
        }
    }

    private func withTimeoutOrRaw(raw: String, _ work: @escaping @Sendable () async -> String) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000)); return nil }
            for await first in group {
                group.cancelAll()
                return first ?? raw
            }
            return raw
        }
    }
}
```

> `mlx-community/Qwen3.5-2B-4bit` is mlx-swift-lm's own integration-test model and loads text-only via `MLXLLM`. Thinking is off by default in its chat template; `enable_thinking: false` is belt-and-suspenders (and required if you fall back to a registered `Qwen3-1.7B-4bit`).

- [ ] **Step 2: Build** (requires the MetalToolchain prerequisite)

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. If it fails with a metallib error at runtime later, confirm `xcodebuild -showComponent MetalToolchain` shows installed.

- [ ] **Step 3: Commit**

```bash
git add App/Sources/System/PolishEngine.swift
git commit -m "feat(app): local LLM polish engine with timeout + raw fallback"
```

---

## Task 11: TextInserter (paste ladder)

Inserts text into the focused app: snapshot the pasteboard, write our text, synthetic ⌘V, then restore the previous clipboard only if we still own it (using `PasteDecision` from Task 6). Falls back to AX direct insertion, then to leaving text on the clipboard.

**Files:**
- Create: `App/Sources/System/TextInserter.swift`

- [ ] **Step 1: Implement**

`App/Sources/System/TextInserter.swift`:
```swift
import AppKit
import ApplicationServices
import MurmurCore

public enum InsertOutcome: Sendable { case pasted, axInserted, leftOnClipboard }

public final class TextInserter {
    public init() {}

    @discardableResult
    public func insert(_ text: String) -> InsertOutcome {
        if axInsert(text) { return .axInserted }      // try direct insert first; no clipboard churn
        if paste(text) { return .pasted }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .leftOnClipboard
    }

    // MARK: - Synthetic paste with ownership-guarded restore
    private func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { dict[type] = d } }
            return dict
        } ?? []

        pb.clearContents()
        pb.setString(text, forType: .string)
        let decision = PasteDecision(ownedChangeCount: pb.changeCount)

        guard postCommandV() else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard decision.shouldRestore(currentChangeCount: pb.changeCount) else { return }
            pb.clearContents()
            for dict in saved {
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                pb.writeObjects([item])
            }
        }
        return true
    }

    private func postCommandV() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)   // 'v'
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
        return vDown != nil && vUp != nil
    }

    // MARK: - Accessibility direct insertion
    private func axInsert(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return false }
        let el = element as! AXUIElement
        // Only safe for elements that expose a settable value/selected-text.
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/Sources/System/TextInserter.swift
git commit -m "feat(app): text inserter with AX insert + guarded synthetic paste"
```

---

## Task 12: AppState + MenuBarExtra wiring

Central observable state plus the menu-bar menu. Sets activation policy to `.accessory` (no Dock icon).

**Files:**
- Create: `App/Sources/AppState.swift`
- Modify: `App/Sources/MurmurApp.swift`

- [ ] **Step 1: Implement AppState**

`App/Sources/AppState.swift`:
```swift
import SwiftUI
import MurmurCore

@MainActor
public final class AppState: ObservableObject {
    public enum Phase: Equatable { case idle, listening(locked: Bool), transcribing, polishing, downloading(Double), error(String) }

    @Published public var phase: Phase = .idle
    @Published public var polishEnabled: Bool = UserDefaults.standard.object(forKey: "polishEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: "polishEnabled") }
    }
    @Published public var hotkey: HotkeyChoice = HotkeyChoice(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "fn") ?? .fn {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: "hotkey") }
    }
    @Published public var recentPeek: [HistoryEntry] = []

    public let history: HistoryStore
    public let vocabulary: VocabularyStore

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
        history = (try? HistoryStore(fileURL: support.appendingPathComponent("history.json"), limit: 200))
            ?? (try! HistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("history.json")))
        vocabulary = (try? VocabularyStore(fileURL: support.appendingPathComponent("vocabulary.json")))
            ?? (try! VocabularyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary.json")))
        recentPeek = Array(history.entries.prefix(3))
    }
}
```

- [ ] **Step 2: Rewrite MurmurApp to use AppState + the real menu**

`App/Sources/MurmurApp.swift`:
```swift
import SwiftUI
import MurmurCore

@main
struct MurmurApp: App {
    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: menuIcon(for: state.phase))
        }

        Window("History", id: "history") { HistoryView(state: state) }
            .windowResizability(.contentSize)
        Settings { SettingsView(state: state) }
    }

    private func menuIcon(for phase: AppState.Phase) -> String {
        switch phase {
        case .idle: return "waveform"
        case .listening: return "waveform.circle.fill"
        case .transcribing, .polishing: return "waveform.badge.magnifyingglass"
        case .downloading: return "arrow.down.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    var body: some View {
        Toggle("Polish with AI", isOn: $state.polishEnabled)
        Divider()
        if state.recentPeek.isEmpty {
            Text("No dictations yet").foregroundStyle(.secondary)
        } else {
            ForEach(state.recentPeek) { entry in
                Button(entry.polished.prefix(40) + (entry.polished.count > 40 ? "…" : "")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.polished, forType: .string)
                }
            }
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Murmur") { NSApplication.shared.terminate(nil) }
    }
}
```
> `HistoryView` and `SettingsView` are created in Tasks 14–15; add minimal stubs now (`struct HistoryView: View { ... Text("History") }`) so the app compiles, then flesh them out.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/AppState.swift App/Sources/MurmurApp.swift
git commit -m "feat(app): AppState + menu-bar menu, accessory activation policy"
```

---

## Task 13: Overlay pill (the hero surface)

A non-activating floating panel, bottom-center, with a live amber waveform and a state label. Springs in/out; degrades to crossfade under Reduce Motion.

**Files:**
- Create: `App/Sources/UI/OverlayPanel.swift`
- Create: `App/Sources/UI/OverlayView.swift`
- Create: `App/Sources/UI/Theme.swift`

- [ ] **Step 1: Theme constants**

`App/Sources/UI/Theme.swift`:
```swift
import SwiftUI

public enum Theme {
    public static let accent = Color(red: 0.96, green: 0.65, blue: 0.14) // ~#F5A623 warm amber
    public static let pillSize = CGSize(width: 280, height: 56)
}
```

- [ ] **Step 2: Non-activating panel**

`App/Sources/UI/OverlayPanel.swift`:
```swift
import AppKit
import SwiftUI

public final class OverlayPanel: NSPanel {
    public init<Content: View>(content: Content) {
        super.init(contentRect: NSRect(origin: .zero, size: Theme.pillSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: content)
        positionBottomCenter()
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - Theme.pillSize.width / 2, y: f.minY + 80))
    }
}
```

- [ ] **Step 3: Overlay SwiftUI view (waveform + label)**

`App/Sources/UI/OverlayView.swift`:
```swift
import SwiftUI

public struct OverlayView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AppState) { self.state = state }

    public var body: some View {
        HStack(spacing: 12) {
            WaveformBars(level: level, animated: !reduceMotion)
                .frame(width: 80, height: 24)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: Theme.pillSize.width, height: Theme.pillSize.height)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    private var level: Float {
        if case .listening = state.phase { return 0.6 } else { return 0.1 }
    }
    private var label: String {
        switch state.phase {
        case .listening(let locked): return locked ? "Listening (locked)" : "Listening"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing…"
        default: return ""
        }
    }
}

struct WaveformBars: View {
    let level: Float
    let animated: Bool
    @State private var phase = 0.0
    var body: some View {
        Canvas { ctx, size in
            let bars = 16
            let w = size.width / CGFloat(bars * 2)
            for i in 0..<bars {
                let n = animated ? (sin(phase + Double(i) * 0.6) * 0.5 + 0.5) : 0.5
                let h = max(2, CGFloat(n) * CGFloat(level) * size.height)
                let x = CGFloat(i) * w * 2 + w
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2), with: .color(Theme.accent))
            }
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/UI/OverlayPanel.swift App/Sources/UI/OverlayView.swift App/Sources/UI/Theme.swift
git commit -m "feat(app): floating overlay pill with amber waveform + reduce-motion support"
```

---

## Task 14: History window

**Files:**
- Create: `App/Sources/UI/HistoryView.swift` (replaces the Task 12 stub)

- [ ] **Step 1: Implement**

`App/Sources/UI/HistoryView.swift`:
```swift
import SwiftUI
import MurmurCore

public struct HistoryView: View {
    @ObservedObject var state: AppState
    @State private var query = ""

    public init(state: AppState) { self.state = state }

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return state.history.entries }
        return state.history.entries.filter { $0.polished.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Search dictations", text: $query)
                .textFieldStyle(.roundedBorder).padding(8)
            Divider()
            List {
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.polished).font(.system(size: 13))
                        HStack {
                            Text(entry.createdAt, style: .relative).font(.system(size: 11, design: .monospaced))
                            Text(entry.appName).font(.system(size: 11))
                        }.foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.polished, forType: .string)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { state.history.delete(id: entry.id); state.recentPeek = Array(state.history.entries.prefix(3)) } }
                }
            }
        }
        .frame(width: 380, height: 480)
    }
}
```

- [ ] **Step 2: Build, then commit**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.
```bash
git add App/Sources/UI/HistoryView.swift
git commit -m "feat(app): history window with search + click-to-copy + delete"
```

---

## Task 15: Settings window + launch at login

**Files:**
- Create: `App/Sources/UI/SettingsView.swift` (replaces the Task 12 stub)

- [ ] **Step 1: Implement**

`App/Sources/UI/SettingsView.swift`:
```swift
import SwiftUI
import ServiceManagement
import MurmurCore

public struct SettingsView: View {
    @ObservedObject var state: AppState
    public init(state: AppState) { self.state = state }

    public var body: some View {
        TabView {
            GeneralTab(state: state).tabItem { Label("General", systemImage: "gearshape") }
            VocabularyTab(state: state).tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 320)
    }
}

struct GeneralTab: View {
    @ObservedObject var state: AppState
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    var body: some View {
        Form {
            Picker("Hotkey", selection: $state.hotkey) {
                Text("Fn (Globe)").tag(HotkeyChoice.fn)
                Text("Right Option").tag(HotkeyChoice.rightOption)
            }
            Toggle("Polish with AI", isOn: $state.polishEnabled)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
                }
        }.padding()
    }
}

struct VocabularyTab: View {
    @ObservedObject var state: AppState
    @State private var newWord = ""
    @State private var words: [String] = []
    var body: some View {
        VStack {
            HStack {
                TextField("Add a name or term", text: $newWord)
                Button("Add") { state.vocabulary.add(newWord); newWord = ""; words = state.vocabulary.words }
            }
            List {
                ForEach(words, id: \.self) { w in
                    HStack { Text(w); Spacer(); Button("Remove") { state.vocabulary.remove(w); words = state.vocabulary.words } }
                }
            }
        }
        .padding()
        .onAppear { words = state.vocabulary.words }
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Murmur").font(.title2.bold())
            Text("Fully local dictation. Audio never leaves your Mac.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Speech: NVIDIA Parakeet (CC-BY-4.0) via FluidAudio").font(.caption2)
            Text("Polish: Qwen3.5-2B via MLX").font(.caption2)
        }.padding()
    }
}
```

- [ ] **Step 2: Build, then commit**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.
```bash
git add App/Sources/UI/SettingsView.swift
git commit -m "feat(app): settings (hotkey, polish, launch-at-login, vocabulary, about)"
```

---

## Task 16: Onboarding + model download

A first-run window that walks permissions then downloads models with progress. Tracks completion in `UserDefaults`.

**Files:**
- Create: `App/Sources/UI/OnboardingView.swift`
- Create: `App/Sources/System/Permissions.swift`

- [ ] **Step 1: Permissions helpers**

`App/Sources/System/Permissions.swift`:
```swift
import AVFoundation
import ApplicationServices

public enum Permissions {
    public static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    public static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
```

- [ ] **Step 2: Onboarding view (permissions + download)**

`App/Sources/UI/OnboardingView.swift`:
```swift
import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var state: AppState
    var onComplete: () -> Void
    @State private var micOK = Permissions.microphoneGranted
    @State private var axOK = Permissions.accessibilityGranted

    public init(state: AppState, onComplete: @escaping () -> Void) {
        self.state = state; self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Murmur").font(.title.bold())
            row("Microphone", "Murmur transcribes your speech on-device.", micOK) {
                Task { micOK = await Permissions.requestMicrophone() }
            }
            row("Accessibility & Input Monitoring", "Needed to detect your hotkey and paste text.", axOK) {
                Permissions.promptAccessibility(); axOK = Permissions.accessibilityGranted
            }
            Text("Tip: set System Settings → Keyboard → “Press 🌐 to” → “Do Nothing” so Fn is free for Murmur.")
                .font(.caption).foregroundStyle(.secondary)
            if case .downloading(let p) = state.phase {
                ProgressView("Downloading models…", value: p)
            }
            Spacer()
            Button("Finish") { onComplete() }.disabled(!(micOK && axOK)).keyboardShortcut(.defaultAction)
        }
        .padding(24).frame(width: 460, height: 360)
    }

    @ViewBuilder private func row(_ title: String, _ why: String, _ ok: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.accent : .secondary)
            VStack(alignment: .leading) { Text(title).bold(); Text(why).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !ok { Button("Grant", action: action) }
        }
    }
}
```

- [ ] **Step 3: Build, then commit**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.
```bash
git add App/Sources/UI/OnboardingView.swift App/Sources/System/Permissions.swift
git commit -m "feat(app): onboarding flow with permissions + model download progress"
```

---

## Task 17: DictationController (the orchestrator)

Ties everything together: receives `DictationEffect`s from `HotkeyMonitor`, runs record → transcribe → polish → insert → history, and drives `AppState.phase` (which the menu icon and overlay observe). This is where the latency budget and the "never lose a dictation" rule are enforced.

**Files:**
- Create: `App/Sources/DictationController.swift`
- Modify: `App/Sources/MurmurApp.swift` (instantiate controller, show overlay)

- [ ] **Step 1: Implement the controller**

`App/Sources/DictationController.swift`:
```swift
import AppKit
import SwiftUI
import MurmurCore

@MainActor
public final class DictationController: HotkeyMonitorDelegate {
    private let state: AppState
    private let recorder = AudioRecorder()
    private let transcriber = TranscriptionEngine()
    private let polisher: PolishEngine
    private let inserter = TextInserter()
    private var monitor: HotkeyMonitor?
    private var overlay: OverlayPanel?
    private var lockedActive = false

    public init(state: AppState) {
        self.state = state
        self.polisher = PolishEngine(minWords: DictationTuning().minPolishWords)
    }

    public func startServices() {
        monitor = HotkeyMonitor(choice: state.hotkey)
        monitor?.delegate = self
        monitor?.start()
        Task {
            state.phase = .downloading(0)
            await transcriber.load { p in Task { @MainActor in self.state.phase = .downloading(p * 0.5) } }
            await polisher.load { p in Task { @MainActor in self.state.phase = .downloading(0.5 + p * 0.5) } }
            self.state.phase = .idle
        }
    }

    // MARK: HotkeyMonitorDelegate
    public func hotkeyDidEmit(_ effect: DictationEffect) {
        switch effect {
        case .startRecording:
            lockedActive = (state.phase == .listening(locked: false)) // second tap path sets locked below
            try? recorder.start()
            // Distinguish hold vs locked by current machine state is internal; show listening.
            state.phase = .listening(locked: lockedActive)
            showOverlay()
        case .finishRecording:
            let samples = recorder.stop()
            runPipeline(samples)
        case .cancelRecording:
            recorder.cancel()
            state.phase = .idle
            hideOverlay()
        case .scheduleTimeout, .none:
            break
        }
    }

    private func runPipeline(_ samples: [Float]) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        Task {
            state.phase = .transcribing
            let raw = (try? await transcriber.transcribe(samples)) ?? ""
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { state.phase = .idle; hideOverlay(); return }
            state.phase = .polishing
            let polished = await polisher.polish(raw, vocabulary: state.vocabulary.words, enabled: state.polishEnabled)
            inserter.insert(polished)
            let entry = HistoryEntry(id: UUID(), raw: raw, polished: polished, createdAt: Date(), appName: appName)
            state.history.append(entry)
            state.recentPeek = Array(state.history.entries.prefix(3))
            state.phase = .idle
            hideOverlay()
        }
    }

    // MARK: Overlay
    private func showOverlay() {
        if overlay == nil { overlay = OverlayPanel(content: OverlayView(state: state)) }
        overlay?.orderFrontRegardless()
    }
    private func hideOverlay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.overlay?.orderOut(nil) }
    }
}
```
> `lockedActive` detection is approximate here; if you want the overlay to show "locked" precisely, expose the machine's mode from `HotkeyMonitor` (add a `var mode: HotkeyMode?` read from `machine.state`) and pass it through the delegate call. Optional polish — the pipeline works either way.

- [ ] **Step 2: Wire the controller into the app**

In `App/Sources/MurmurApp.swift`, add to `MurmurApp`:
```swift
    @State private var controller: DictationController?
```
and attach a launch hook on the menu label or a hidden `.task`:
```swift
        .task {
            if controller == nil {
                let c = DictationController(state: state)
                controller = c
                c.startServices()
            }
        }
```
(Attach `.task` to `MenuContent` or wrap the `MenuBarExtra` label in a view that owns it.)

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/DictationController.swift App/Sources/MurmurApp.swift
git commit -m "feat(app): dictation controller orchestrating the full pipeline"
```

---

## Task 18: Menu-bar icon state polish

The icon already switches by phase in Task 12. This task adds the amber tint and pulse for active states via a tiny `NSStatusItem` treatment if the SF Symbol tint needs to be explicit (SwiftUI `MenuBarExtra` renders template images monochrome by default).

**Files:**
- Modify: `App/Sources/MurmurApp.swift`

- [ ] **Step 1: Apply rendering mode + amber for active phases**

In the `MenuBarExtra` label, replace the bare `Image` with:
```swift
        } label: {
            Image(systemName: menuIcon(for: state.phase))
                .symbolRenderingMode(.palette)
                .foregroundStyle(isActive(state.phase) ? Theme.accent : Color.primary)
        }
```
and add:
```swift
    private func isActive(_ phase: AppState.Phase) -> Bool {
        switch phase { case .idle, .error: return false; default: return true }
    }
```

- [ ] **Step 2: Build, then commit**

Run: `xcodebuild -scheme Murmur -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.
```bash
git add App/Sources/MurmurApp.swift
git commit -m "feat(app): amber menu-bar icon tint for active states"
```

---

## Task 19: End-to-end verification

No new code — a manual checklist run against a real launch, plus design verification with screenshots per the workspace Asset/Verification protocol.

- [ ] **Step 1: Launch the built app**

Run: `open ~/Library/Developer/Xcode/DerivedData/Murmur-*/Build/Products/Debug/Murmur.app`
(Or run from Xcode.) Complete onboarding; grant permissions; wait for model downloads.

- [ ] **Step 2: Functional checklist** — verify and record PASS/FAIL for each:
  - Hold Fn, speak a sentence, release → polished text appears in TextEdit within ~1.5s.
  - Hold Fn, speak, release with polish disabled → raw-but-present text within ~300ms.
  - Double-tap Fn → overlay shows "Listening (locked)"; speak hands-free; single tap → text inserted.
  - Press Esc mid-recording → nothing inserted, overlay fades.
  - Paste into Slack, a browser field, and Terminal → text lands; clipboard contents restored afterward.
  - Copy something, dictate, confirm your copied text is still on the clipboard (ownership guard).
  - Switch hotkey to Right Option in Settings → works without restart-or with documented restart.
  - History window shows entries, click-to-copy works, delete works.
  - Add a vocabulary word, dictate it misspelled → polish corrects it.
  - Quit and relaunch → launch-at-login state persists; history persists.

- [ ] **Step 3: Design verification (screenshots)**

Capture the overlay pill, menu, history, and settings. Compare against the spec's UI/UX section: amber accent only on live states, monochrome elsewhere, dense calm hierarchy, springs (or crossfades under Reduce Motion). Record whether each surface matches; note any drift to fix.

- [ ] **Step 4: Run the full core test suite once more**

Run: `cd MurmurCore && swift test`
Expected: all pure-logic tests PASS.

- [ ] **Step 5: Commit any fixes from verification**

```bash
git add -A && git commit -m "fix(app): address issues found in end-to-end verification"
```

---

## Self-Review Notes (completed by plan author)

- **Spec coverage:** Every spec component maps to a task — HotkeyMonitor→T2/T7, AudioRecorder→T8, TranscriptionEngine→T9, PolishEngine→T5/T10, TextInserter→T6/T11, OverlayWindow→T13, HistoryStore→T4/T14, VocabularyStore→T3/T15, Settings→T15, PermissionsCoordinator→T16, plus orchestration (T17) and the five UI surfaces from the UI/UX section (T12–T16, T18). Privacy posture is enforced by AudioRecorder (in-memory only) and the local stores.
- **Build reality:** the MetalToolchain prerequisite and `xcodebuild`-vs-`swift build` split are called out so the executor doesn't hit the metallib crash. Pure logic stays in `swift test`.
- **Type consistency:** `DictationEffect`, `HotkeyChoice`, `HistoryEntry`, `PasteDecision`, `PolishPromptBuilder`, `AppState.Phase`, and `Theme` are defined once and referenced with identical names throughout.
- **Known soft spots (acceptable for v1, flagged inline):** the controller's `lockedActive` detection is approximate (T17 note); FluidAudio API specifics are pinned but the SDK moves fast (T9 note tells the executor exactly where to verify); the `scheduleTimeout` effect case is reserved rather than returned (the controller arms timers off `pendingTimeout`).
