# Murmur — Local Dictation for macOS — Design Spec

**Date:** 2026-06-12
**Status:** Approved
**Goal:** A free, fully-local Wispr Flow replacement. Hold a key, speak, polished text lands in whatever app has focus. Nothing leaves the machine.

## Requirements (user-confirmed)

| Decision | Choice |
|---|---|
| Form factor | Native menu-bar Mac app (no Dock icon), free, fully local |
| Trigger | Hold-to-talk (push-to-talk) + double-tap to lock for long dictation; Esc cancels |
| Languages | English only |
| Speech-to-text | NVIDIA Parakeet tdt-0.6b-v2 (best local English model) |
| Cleanup | Light local-LLM polish: remove fillers, repair false starts, apply custom vocabulary |
| V1 extras | Recording overlay, dictation history, custom vocabulary, launch at login |

**Target hardware/OS:** Apple Silicon, macOS 15+. Developed on M4 Max / 36GB / macOS 15.7 / Xcode 26.3 / Swift 6.

## Architecture

Single-process SwiftUI app using `MenuBarExtra`, `LSUIElement = true`. No servers, no Python sidecar, no Ollama — both models run in-process.

**Dependencies (verified current 2026-06-12, pin both):**

| Package | Version | License | Role |
|---|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | from: 0.15.2 | Apache-2.0 | Parakeet v2 ASR on CoreML/ANE (~145x real-time on M4-class) |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | from: 3.31.3 | MIT | Embedded LLM (Qwen3.5-2B-4bit) for the polish pass |

Model weights download from Hugging Face on first launch (Parakeet ~0.5–1GB + Qwen3.5-2B ~1.3GB; confirm exact sizes during implementation), cached locally; fully offline afterward. Parakeet upstream weights are CC-BY-4.0 — include attribution in the About screen.

## Components

| Component | Responsibility | Key constraints |
|---|---|---|
| `HotkeyMonitor` | CGEventTap on `keyDown/keyUp/flagsChanged`. State machine: `idle → holdRecording` (key held), `idle → lockedRecording` (double-tap within threshold, default 300ms — tunable constant), Esc → cancel. Fn key = keycode 63 / `.maskSecondaryFn` flag; track Fn state separately because the flag bleeds into arrow/function keys. Watchdog: poll `AXIsProcessTrusted` ~100ms and re-enable tap on `.tapDisabledByTimeout`. | Requires Accessibility + Input Monitoring permissions. Default key Fn; Right-Option offered as the zero-config alternative. |
| `AudioRecorder` | AVAudioEngine mic capture at native rate → convert to 16kHz mono Float32 (FluidAudio's `AudioConverter`) → in-memory buffer. | Audio never touches disk. Handle device disappearance mid-recording. |
| `TranscriptionEngine` | Wraps FluidAudio `AsrManager`, Parakeet v2 loaded once at app launch (cold CoreML compile ~3s happens here, not per-utterance). Buffer in → text out. | Batch transcription on key release; no streaming (streaming model is less accurate). Verify exact API against pinned v0.15.x source (docs show both `loadModels` and `configure`). |
| `PolishEngine` | mlx-swift-lm `ChatSession`, Qwen3.5-2B-4bit, thinking disabled via chat-template kwargs (`enable_thinking: false`) — verify the rendered template omits the think block or latency explodes. System prompt: strip fillers, repair false starts ("Tuesday— no, Wednesday" → "Wednesday"), apply custom vocabulary corrections, preserve meaning, output cleaned text only. | Skipped for utterances under 4 words (tunable constant). User toggle to disable entirely. 3s timeout → fall back to raw transcript. Model resident in memory. |
| `TextInserter` | Paste ladder: (1) snapshot full pasteboard (all types) → write text → synthetic ⌘V via CGEvent (keycodes 55+9) → restore after ≥250ms only if we still own the pasteboard (session-ID guard); (2) AX direct insert via `kAXFocusedUIElement` for apps that rebind ⌘V; (3) on total failure, leave text on clipboard + notify. | The ownership guard prevents clobbering a user copy that raced the restore. |
| `OverlayWindow` | Non-activating floating NSPanel pill, bottom-center. States: listening / locked / transcribing / polishing, with live input level. | Must never steal focus from the target app. |
| `HistoryStore` | Last ~200 dictations (raw + polished + timestamp + target app) in flat JSON at `~/Library/Application Support/Murmur/history.json`. History window: list + click-to-copy. | Local only, user-deletable. |
| `VocabularyStore` | User word list (names, jargon) in `vocabulary.json`, edited in Settings, injected into the polish system prompt. | |
| `Settings` | Hotkey choice, polish on/off, launch at login (`SMAppService`), vocabulary editor. Preferences in `UserDefaults`. | |
| `PermissionsCoordinator` | First-run onboarding: mic permission → Accessibility → Input Monitoring → Fn-key system setting guidance ("Press Fn to: Do Nothing") → model downloads with progress. | Dictation disabled until models are ready; menu-bar icon shows download progress. |

## Data flow

**Hold mode:** Fn down → `HotkeyMonitor` → `AudioRecorder.start` + overlay "listening" → Fn up → stop capture → `TranscriptionEngine.transcribe` (~100ms) → `PolishEngine.polish` (~0.5–1s, skipped if <4 words) → `TextInserter.insert` → `HistoryStore.append` → overlay fades.

**Lock mode:** double-tap Fn → same pipeline, recording continues until a single tap ends it.

**Cancel:** Esc at any point during recording → discard buffer, overlay fades, nothing inserted.

**Latency budget:** key-release → text under 1.5s typical with polish; under 300ms with polish skipped.

## Error handling

Rule: **never lose a dictation.**

| Failure | Behavior |
|---|---|
| Polish fails / exceeds 3s | Insert raw transcript (worse-but-present beats a spinner) |
| No focused text field | Text stays on clipboard + notification |
| Models not yet downloaded | Menu-bar progress; dictation disabled until ready |
| Event tap silently disabled | Watchdog re-enables; permission revoked → warning icon + fix-it link |
| Mic device vanishes mid-recording | Transcribe what was captured |

## Testing

- **Unit (XCTest):** hotkey state machine transitions (incl. double-tap timing threshold), vocabulary injection into the polish prompt, history store round-trip, pasteboard-restore ownership guard. All pure logic behind protocols; no mocking frameworks.
- **Integration (manual trigger, not per-build):** bundled WAV fixture → transcript must contain known words. Loads the real 600MB model, so excluded from the default test plan.
- **Manual checklist:** permissions flow, paste behavior across apps (TextEdit, Slack, browser, terminal), Fn vs Right-Option, lock mode, Esc cancel, clipboard restore.

## Privacy posture

Audio is never written to disk. No network calls except first-launch model downloads from Hugging Face. History is one local JSON file the user can delete. This is the product's reason to exist.

## Out of scope (v2 candidates)

Multilingual (Parakeet v3 swap), per-app tone profiles, command mode, streaming partial transcripts, App Store distribution/notarization (local ad-hoc signing is fine for personal use), macOS 26 `SpeechAnalyzer`/FoundationModels adoption.

## Prior art & patterns borrowed

- **Hex** (MIT): Fn-hold CGEventTap pattern (`.maskSecondaryFn`, separate Fn state tracking, tap watchdog); AX direct-insert fallback.
- **VoiceInk** (GPL-3 — patterns referenced, no code copied): pasteboard session-ID ownership guard; paste-method user setting.
- Research basis: FluidAudio v0.15.2 benchmarks (2.1% WER, ~146x RTF on M4 Pro); Qwen3.5-2B-4bit est. 0.5–0.8s for ~100-word cleanup on M4 Max (extrapolated, benchmark locally before tuning timeouts).
