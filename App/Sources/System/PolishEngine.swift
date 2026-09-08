import Foundation
import HuggingFace
import Tokenizers
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import MurmurCore

public actor PolishEngine {
    public enum LoadState: Sendable { case unloaded, loading, ready, failed(String) }
    public private(set) var loadState: LoadState = .unloaded

    private var generating = false
    private var container: ModelContainer?
    private let builder: PolishPromptBuilder
    private let timeout: TimeInterval

    public init(minWords: Int, timeout: TimeInterval = 3.0) {
        self.builder = PolishPromptBuilder(minWords: minWords)
        self.timeout = timeout
    }

    public func load(progress: (@Sendable (Double) -> Void)? = nil) async {
        if case .ready = loadState { return }
        loadState = .loading
        do {
            let c: ModelContainer
            if let progress {
                c = try await #huggingFaceLoadModelContainer(
                    configuration: ModelConfiguration(id: "mlx-community/Qwen3.5-2B-4bit"),
                    progressHandler: { p in progress(p.fractionCompleted) }
                )
            } else {
                c = try await #huggingFaceLoadModelContainer(
                    configuration: ModelConfiguration(id: "mlx-community/Qwen3.5-2B-4bit")
                )
            }
            container = c
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Returns polished text, or the raw transcript unchanged if polishing is
    /// skipped (too short), disabled, times out, or errors. Never throws.
    public func polish(_ raw: String, vocabulary: [String], enabled: Bool) async -> String {
        guard !generating, enabled, builder.shouldPolish(raw), let container, case .ready = loadState else {
            return raw
        }
        let system = builder.systemPrompt(vocabulary: vocabulary)
        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.3),
            additionalContext: ["enable_thinking": false]
        )
        // Keep only one generation in flight, even if cancellation is delayed.
        generating = true
        let work = Task {
            defer { generating = false }
            let result = (try? await session.respond(to: raw))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
            return result.isEmpty ? raw : result
        }
        return await timedResult(of: work, timeout: .seconds(timeout), fallback: raw)
    }
}
