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
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | exact: 0.15.2 | Apache-2.0 | Parakeet v2 ASR on CoreML/ANE (~145x real-time on M4-class) |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | upToNextMajor 3.31.3 | MIT | Embedded LLM (`mlx-community/Qwen3.5-2B-4bit`) for the polish pass |

Plus transitive deps mlx-swift-lm requires explicit: `swift-huggingface` (0.9.0) and `swift-transformers` (1.3.x). Link only `MLXLLM` + `MLXLMCommon` + `MLXHuggingFace` — **not** `MLXVLM` (its factory resolves the Qwen3.5 checkpoint down the vision path; MLXLLM alone loads it text-only).

Model weights download from Hugging Face on first launch (Parakeet ~600MB → `~/Library/Application Support/FluidAudio/Models/`, Qwen3.5-2B-4bit ~1.5GB → `~/.cache/huggingface/hub/`), cached locally; fully offline afterward. Parakeet upstream weights are CC-BY-4.0 — include attribution in the About screen.

**Build system (important):** MLX compiles Metal shaders, which plain `swift build`/`swift test` does **not** handle — a native-SPM binary builds but crashes at first MLX eval (`Failed to load the default metallib`). So the project is an **Xcode project** (or SPM package built via `xcodebuild -scheme <name>-Package -destination 'platform=macOS'`), and the Xcode 26 **MetalToolchain** component must be installed once via `xcodebuild -downloadComponent MetalToolchain`. Pure-logic tests (hotkey state machine, stores) can still run under `swift test`; any test that evaluates an MLX graph must run via the Xcode scheme.

## Components

| Component | Responsibility | Key constraints |
|---|---|---|
| `HotkeyMonitor` | CGEventTap on `keyDown/keyUp/flagsChanged`. State machine: `idle → holdRecording` (key held), `idle → lockedRecording` (double-tap within threshold, default 300ms — tunable constant), Esc → cancel. Fn key = keycode 63 / `.maskSecondaryFn` flag; track Fn state separately because the flag bleeds into arrow/function keys. Watchdog: poll `AXIsProcessTrusted` ~100ms and re-enable tap on `.tapDisabledByTimeout`. | Requires Accessibility + Input Monitoring permissions. Default key Fn; Right-Option offered as the zero-config alternative. |
| `AudioRecorder` | AVAudioEngine mic capture at native rate → convert to 16kHz mono Float32 (FluidAudio's `AudioConverter`) → in-memory buffer. | Audio never touches disk. Handle device disappearance mid-recording. |
| `TranscriptionEngine` | Wraps FluidAudio `AsrManager` (an actor), Parakeet v2 loaded once at app launch via `AsrModels.downloadAndLoad(version: .v2)` + `loadModels(_:)` (cold CoreML compile ~3s happens here, not per-utterance). Per utterance: fresh `TdtDecoderState.make(decoderLayers: await mgr.decoderLayerCount)`, then `transcribe(_ samples: [Float], decoderState: &state)` → `ASRResult.text`. | Batch transcription on key release; no streaming (streaming model is less accurate). Note: v0.15.2 has no `transcribe(_:source:)` / `configure(_:)` — those appear only in stale docs. |
| `PolishEngine` | mlx-swift-lm `ChatSession`, Qwen3.5-2B-4bit, thinking disabled via chat-template kwargs (`enable_thinking: false`) — verify the rendered template omits the think block or latency explodes. System prompt: strip fillers, repair false starts ("Tuesday— no, Wednesday" → "Wednesday"), apply custom vocabulary corrections, preserve meaning, output cleaned text only. | Skipped for utterances under 4 words (tunable constant). User toggle to disable entirely. 3s timeout → fall back to raw transcript. Model resident in memory. |
| `TextInserter` | Paste ladder: (1) snapshot full pasteboard (all types) → write text → synthetic ⌘V via CGEvent (keycodes 55+9) → restore after ≥250ms only if we still own the pasteboard (session-ID guard); (2) AX direct insert via `kAXFocusedUIElement` for apps that rebind ⌘V; (3) on total failure, leave text on clipboard + notify. | The ownership guard prevents clobbering a user copy that raced the restore. |
| `OverlayWindow` | Non-activating floating NSPanel pill, bottom-center. States: listening / locked / transcribing / polishing, with live input level. | Must never steal focus from the target app. |
| `HistoryStore` | Last ~200 dictations (raw + polished + timestamp + target app) in flat JSON at `~/Library/Application Support/Murmur/history.json`. History window: list + click-to-copy. | Local only, user-deletable. |
| `VocabularyStore` | User word list (names, jargon) in `vocabulary.json`, edited in Settings, injected into the polish system prompt. | |
| `Settings` | Hotkey choice, polish on/off, launch at login (`SMAppService`), vocabulary editor. Preferences in `UserDefaults`. | |
| `PermissionsCoordinator` | First-run onboarding: mic permission → Accessibility → Input Monitoring → Fn-key system setting guidance ("Press Fn to: Do Nothing") → model downloads with progress. | Dictation disabled until models are ready; menu-bar icon shows download progress. |

## UI/UX & Design Inspiration

**Design philosophy:** Linear-inspired precision. Dark-first, monochromatic, dense but calm hierarchy, purposeful motion, Refactoring UI fundamentals (spacing and weight do the work, not borders and color). The app should feel like a native macOS citizen that a precise tool-maker built — invisible until summoned, exact when present.

**Named inspirations:**

| Source | What we take |
|---|---|
| **Linear** | Monochrome + single accent, keyboard-first, restraint, spring-based motion, the feeling that every pixel is deliberate |
| **Wispr Flow / superwhisper** | The floating-pill interaction as the hero moment; the app's entire visible footprint during use is one small, beautiful object |
| **Raycast** | Menu-bar and settings surfaces that feel native but elevated; quiet command-surface polish |
| **macOS system (SwiftUI + AppKit)** | Vibrancy materials, SF Symbols, SF Pro, NSPanel behavior — so nothing looks bolted on |

**Accent:** Warm amber (~`#F5A623`) for live/active states only. Everything else is a monochrome gray ramp on a dark base. Amber means "the mic is hot or the pipeline is working" — it is the one place color is allowed to speak.

**The five surfaces:**

1. **Menu-bar icon** — a single SF Symbol glyph (`waveform`). State by treatment, not extra chrome: idle = monochrome template; recording = amber + subtle pulse; transcribing/polishing = amber with an indeterminate shimmer; downloading = progress ring; error = `exclamationmark.triangle` warning tint. Reads at 1× and 2× menu-bar height.

2. **Recording overlay pill** (the hero) — non-activating `NSPanel`, bottom-center, ~280×56pt, heavy vibrancy material, fully rounded. Springs in (scale 0.9→1.0 + fade, ~180ms) on record start, springs out on completion. Contents: a live waveform/level meter (amber, real input amplitude, smoothed), and a compact state label — `Listening` · `Listening (locked)` · `Transcribing…` · `Polishing…`. Lock mode shows a small lock glyph. Never steals focus. Honors Reduce Motion (crossfade instead of spring, static bars instead of animated waveform).

3. **Menu-bar dropdown** — `MenuBarExtra` menu: a Polish on/off toggle, Pause dictation, the last 3 dictations as click-to-copy peek rows, then Open History, Settings…, Quit. Dense, native, keyboard-navigable.

4. **History window** — single-column SwiftUI `List` of dictation cards (polished text, faded raw text on hover/expand, relative timestamp, target-app glyph). Click to copy, swipe/⌫ to delete, search field at top. Dark, dense, monospaced timestamps.

5. **Settings window** — standard macOS `Settings` scene with tabs: General (hotkey picker, launch-at-login, polish toggle + skip-threshold), Vocabulary (add/remove word list, live-editable), About (model versions, attribution, privacy statement). Native `Form` styling.

6. **Onboarding** (first run) — a short, calm, single-window flow: one card per permission (Microphone → Accessibility → Input Monitoring → Fn-key guidance), each with a plain-language "why" line and a single primary button; then a model-download screen with real progress. Tone: formal, short declarative sentences, no hand-holding fluff.

**Motion principles:** Springs for presence (pill in/out), crossfades for state changes (label swaps), no motion that isn't communicating a state change. Everything degrades to crossfade under Reduce Motion — and tests run in reduced-motion for determinism.

**Voice/copy:** Formal, short, declarative, active. No emoji, no exclamation marks in UI strings, no "Oops!" — a precise tool talks plainly.

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
