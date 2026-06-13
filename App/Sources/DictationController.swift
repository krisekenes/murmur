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
    private var pendingHide: DispatchWorkItem?

    public init(state: AppState) {
        self.state = state
        self.polisher = PolishEngine(minWords: DictationTuning().minPolishWords)
    }

    public func startServices() {
        let monitor = HotkeyMonitor(choice: state.hotkey)
        monitor.delegate = self
        monitor.start()
        self.monitor = monitor
        Task { await loadModels() }
    }

    private func loadModels() async {
        state.phase = .downloading(0)
        await transcriber.load { p in Task { @MainActor in self.state.phase = .downloading(p * 0.5) } }
        if case .failed(let msg) = await transcriber.loadState {
            state.phase = .error("Speech model failed to load: \(msg)")
            return
        }
        await polisher.load { p in Task { @MainActor in self.state.phase = .downloading(0.5 + p * 0.5) } }
        // Polish is optional; if it fails we still dictate (raw transcript), so don't hard-error.
        state.phase = .idle
    }

    // MARK: HotkeyMonitorDelegate
    public func hotkeyDidEmit(_ effect: DictationEffect, mode: HotkeyMode?) {
        switch effect {
        case .startRecording:
            try? recorder.start()
            state.phase = .listening(locked: mode == .locked)
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
            let raw = ((try? await transcriber.transcribe(samples)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { state.phase = .idle; hideOverlay(); return }
            state.phase = .polishing
            let polished = await polisher.polish(raw, vocabulary: state.vocabulary.words, enabled: state.polishEnabled)
            inserter.insert(polished)
            state.history.append(HistoryEntry(id: UUID(), raw: raw, polished: polished, createdAt: Date(), appName: appName))
            state.recentPeek = Array(state.history.entries.prefix(3))
            state.phase = .idle
            hideOverlay()
        }
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
