import Foundation
import FluidAudio

public actor TranscriptionEngine {
    public enum LoadState: Sendable { case unloaded, loading, ready, failed(String) }
    public private(set) var loadState: LoadState = .unloaded

    private var manager: AsrManager?

    public init() {}

    /// Call once at launch (cold CoreML compile happens here, ~3s).
    public func load(progress: (@Sendable (Double) -> Void)? = nil) async {
        if case .ready = loadState { return }
        loadState = .loading
        do {
            let progressHandler: DownloadUtils.ProgressHandler? = progress.map { cb -> DownloadUtils.ProgressHandler in
                { (downloadProgress: DownloadUtils.DownloadProgress) in cb(downloadProgress.fractionCompleted) }
            }
            let models = try await AsrModels.downloadAndLoad(
                version: .v2,
                progressHandler: progressHandler
            )
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
