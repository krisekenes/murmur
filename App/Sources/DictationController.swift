import AppKit
import SwiftUI
import Combine
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
    private var pendingHide: DispatchWorkItem?
    private var levelTimer: Timer?
    private var transcriberReady = false
    private var loadingModels = false
    private var loadStage = UUID()
    private var hotkeySubscription: AnyCancellable?
    private var pipelineRunning = false
    private var recording = false
    private var lastInsertAt: Date?
    private var lastInsertApp: String?

    public init(state: AppState) {
        self.state = state
        self.polisher = PolishEngine(minWords: DictationTuning().minPolishWords)
    }

    public func startServices() {
        restartHotkey()
        hotkeySubscription = state.$hotkey.dropFirst().removeDuplicates().sink { [weak self] choice in
            self?.restartHotkey(choice: choice)
        }
        state.retryModels = { [weak self] in
            guard let self else { return }
            Task { await self.loadModels() }
        }
        Task { await loadModels() }
    }

    public func restartHotkey(choice: HotkeyChoice? = nil) {
        monitor?.stop()
        if recording {
            recorder.cancel()
            recording = false
            stopLevelMetering()
            state.phase = .idle
            hideOverlay()
        }
        let monitor = HotkeyMonitor(choice: choice ?? state.hotkey)
        monitor.delegate = self
        monitor.start()
        self.monitor = monitor
    }

    private func loadModels() async {
        guard !loadingModels, !recording, !pipelineRunning else { return }
        loadingModels = true
        transcriberReady = false
        state.canRetryModels = false
        state.notice = nil
        defer { loadingModels = false; loadStage = UUID() }
        state.phase = .downloading(0)
        loadStage = UUID()
        let speechStage = loadStage
        await transcriber.load { p in
            Task { @MainActor in
                guard self.loadStage == speechStage else { return }
                self.state.phase = .downloading(p * 0.5)
            }
        }
        if case .failed(let msg) = await transcriber.loadState {
            state.phase = .error("Speech model failed to load: \(msg)")
            state.canRetryModels = true
            return
        }
        loadStage = UUID()
        let polishStage = loadStage
        await polisher.load { p in
            Task { @MainActor in
                guard self.loadStage == polishStage else { return }
                self.state.phase = .downloading(0.5 + p * 0.5)
            }
        }
        if case .failed = await polisher.loadState {
            state.notice = "AI cleanup is unavailable. You can still dictate without it."
            state.canRetryModels = true
        }
        transcriberReady = true
        state.phase = .idle
    }

    // MARK: HotkeyMonitorDelegate
    public func hotkeyDidEmit(_ effect: DictationEffect, mode: HotkeyMode?) {
        guard transcriberReady else { return }
        switch effect {
        case .startRecording:
            guard !pipelineRunning, !recording else { return }
            do {
                try recorder.start()
            } catch {
                state.phase = .error("Microphone unavailable")
                return
            }
            state.notice = nil
            recording = true
            state.phase = .listening(locked: mode == .locked)
            showOverlay()
            startLevelMetering()
        case .finishRecording:
            guard recording else { return }
            recording = false
            let samples = recorder.stop()
            stopLevelMetering()
            runPipeline(samples)
        case .cancelRecording:
            guard recording else { return }
            recording = false
            recorder.cancel()
            stopLevelMetering()
            state.phase = .idle
            hideOverlay()
        case .scheduleTimeout, .none:
            break
        }
    }

    private func runPipeline(_ samples: [Float]) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        pipelineRunning = true
        Task {
            defer { pipelineRunning = false }
            state.phase = .transcribing
            let raw: String
            do {
                raw = try await transcriber.transcribe(samples).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                state.phase = .error("Transcription failed: \(error.localizedDescription)")
                hideOverlay()
                return
            }
            guard !raw.isEmpty else { state.phase = .idle; hideOverlay(); return }
            state.phase = .polishing
            let polished = await polisher.polish(raw, vocabulary: state.vocabulary.words, enabled: state.polishEnabled)
            // Prepend a space when continuing dictation into the same app, so sentences are
            // separated. A leading space (between content) renders in native and web fields
            // alike; a trailing space gets collapsed by web inputs.
            let isContinuation = lastInsertApp == appName
                && (lastInsertAt.map { Date().timeIntervalSince($0) < 30 } ?? false)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                let outcome = inserter.insert((isContinuation ? " " : "") + polished)
                if case .leftOnClipboard = outcome {
                    state.notice = "Text copied to clipboard. Press Command-V to paste it."
                    lastInsertAt = nil
                    lastInsertApp = nil
                } else {
                    lastInsertAt = Date()
                    lastInsertApp = appName
                }
            } else {
                // Never paste into a different app after the user switches away.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(polished, forType: .string)
                state.notice = "App changed. Text copied to clipboard; press Command-V to paste it."
                lastInsertAt = nil
                lastInsertApp = nil
            }
            state.appendDictation(HistoryEntry(id: UUID(), raw: raw, polished: polished, createdAt: Date(), appName: appName))
            state.phase = .idle
            hideOverlay()
        }
    }

    private func startLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; the controller is @MainActor.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.inputLevel = self.recorder.currentLevel
            }
        }
    }

    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
        state.inputLevel = 0
    }

    // MARK: Overlay (cancellable hide so a double-tap doesn't get hidden by a stale timer)
    private func showOverlay() {
        pendingHide?.cancel()
        pendingHide = nil
        if overlay == nil { overlay = OverlayPanel(content: OverlayView(state: state)) }
        overlay?.orderFrontRegardless()
    }

    private func hideOverlay() {
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.overlay?.orderOut(nil) }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
