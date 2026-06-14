# Murmur — UI/UX Pass + Main Window + Icon — Design Spec

**Date:** 2026-06-13
**Status:** Approved
**Builds on:** the shipped menu-bar dictation app (overlay pill, history store, settings, onboarding, working insert pipeline).

## Goal

Give Murmur a real primary surface — a Wispr Flow-style main window combining a searchable feed of past dictations with an editable scratchpad you can dictate into — plus a proper app icon, and a consistent visual polish pass across the app.

## Decisions (user-confirmed)

| Decision | Choice |
|---|---|
| Main window | New primary window, sidebar split: feed (left) + scratchpad (right) |
| Notepad role | Both — a running editable scratchpad AND a searchable feed of past dictations |
| Dictation → scratchpad | Focus-based, no new mode: dictation lands in the scratchpad when Murmur's window is focused; otherwise inserts into the external app as today. Every dictation logs to the feed. |
| Icon | Amber waveform bars on a dark macOS squircle (matches overlay + menu glyph) |
| Name | Murmur (confirmed) |

## Main window

A `Window` scene titled "Murmur", summoned from the menu bar (the current "History…" menu item becomes "Open Murmur"; add `openWindow(id: "main")`). The app stays `.accessory` (no Dock icon); the window is the rich surface when summoned.

**Layout — sidebar split (`NavigationSplitView` or `HSplitView`):**

- **Top bar:** "Murmur" title; global search field (filters the feed); a live status dot mirroring `AppState.phase` (idle = dim, listening/transcribing/polishing = amber); settings gear (opens Settings scene).
- **Left — FeedView (~40% width):** date-grouped (`Today`, `Yesterday`, older) list of `HistoryEntry` cards. Each card shows the polished text (2-3 line clamp), a monospaced timestamp, and the source-app name/glyph. Hover reveals a copy button. Click → append the entry's text into the scratchpad. Swipe / ⌫ → delete. Search filters by text.
- **Right — ScratchpadView (~60% width):** a large editable `TextEditor` with comfortable typography and a quiet "Dictate or type…" placeholder. Footer: `Copy` and `Clear` buttons. Content persists across launches.

## Dictation targeting (reuses the existing pipeline)

No parallel insertion path. The scratchpad is an ordinary focused `TextEditor`:
- Murmur window focused + scratchpad active → the existing `TextInserter` ⌘V path inserts dictation into the scratchpad (it's the focused field).
- Any other app focused → inserts there, as today.
- Every completed dictation is appended to the feed (history) regardless, exactly as now.

The controller already records each dictation to the feed; no change needed there beyond ensuring the main window observes the same `AppState`.

## Components

| Component | Responsibility | Notes |
|---|---|---|
| `MainWindowView` | Hosts the split: top bar + FeedView + ScratchpadView. Observes `AppState`. | New. The single primary window. |
| `FeedView` | Date-grouped, searchable list of `HistoryEntry` cards; copy / append-to-scratchpad / delete. | Replaces the standalone `HistoryView` window (absorbed). |
| `FeedCard` | One dictation card: text, timestamp, source app, hover copy. | New small view. |
| `ScratchpadView` | Editable `TextEditor` bound to `ScratchpadStore`; Copy/Clear; placeholder. | New. |
| `ScratchpadStore` | Persisted plain-text note at `~/Library/Application Support/Murmur/scratchpad.txt`. Load on init, debounced save on change. | New, in `MurmurCore` (pure + unit-tested, consistent with `HistoryStore`/`VocabularyStore`). Plain text only. |
| `StatusDot` | Small amber/dim dot reflecting `AppState.phase`. | New, shared with menu/overlay vocabulary. |
| `AppState` | Add `@Published scratchpad: String` (mirrors the store) + window-open plumbing. | Modify. |
| Icon asset | `Assets.xcassets/AppIcon.appiconset` with all sizes 16–1024, generated from a vector waveform-on-squircle. | New. Replaces blank default. |

## App icon

Amber (`#F5A623`) waveform bars, vertically centered, on a dark (near-black, subtle vertical gradient) rounded square using the macOS icon grid/squircle with standard padding. Generated programmatically (vector → PNG at each size → `iconutil`/asset catalog). Sizes: 16, 32, 64, 128, 256, 512, 1024 (1× and 2×). **A rendered screenshot is shown to the user for approval before finalizing** (two-strike rule: if two iterations don't improve, switch technique).

## Visual polish pass

Apply consistently, grounded in the Linear-inspired direction (dark-first, monochrome + amber accent, dense calm hierarchy, Refactoring UI fundamentals):
- Feed cards: rounded, subtle borders/elevation, hover states, monospaced timestamps.
- Scratchpad: editor typography, generous padding.
- Settings + onboarding: refresh spacing, apply the amber accent, refine copy (formal, short, active — no emoji in UI strings).
- Motion: spring for window/panel presence, crossfade for state changes; all degrade under Reduce Motion.

## Cleanup folded into this pass

- Remove the temporary file-based debug logging (`DebugLog.swift`, `murmurDebug` calls, the launch marker) added while fixing the insert bug.
- Commit the verified bug fixes from the debugging session: paste-first insertion (⌘V primary, AX fallback) and leading-space-on-continuation spacing.

## Data flow

Dictation pipeline unchanged. New: `ScratchpadStore` ⇄ `AppState.scratchpad` ⇄ `ScratchpadView` (two-way binding, debounced persistence). `FeedView` reads `AppState.historyEntries`; append-to-scratchpad mutates `AppState.scratchpad`.

## Error handling

- Scratchpad persistence failures are non-fatal (in-memory continues; corrupt file set aside like the other stores).
- Main window observes the single shared `AppState`; no second source of truth.

## Testing

- **Unit (MurmurCore, `swift test`):** `ScratchpadStore` round-trip (load/save/clear, corrupt-file handling), feed date-grouping helper.
- **Manual / screenshot:** icon at 16/32/512; main window light/dark; dictate-into-scratchpad while focused; dictate-into-other-app still works; feed search/copy/append/delete; reduce-motion.

## Out of scope (later)

Cloud sync, multiple notes/notebooks, rich-text formatting, per-app tone, exporting, a dedicated "capture mode" hotkey.
