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
        guard enabled, builder.shouldPolish(raw), let container, case .ready = loadState else {
            return raw
        }
        let system = builder.systemPrompt(vocabulary: vocabulary)
        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.3),
            additionalContext: ["enable_thinking": false]
        )
        // Race generation against a hard timeout. `session` is not Sendable, but it
        // is captured only by `work`, an actor-isolated Task; the task group's child
        // closures capture only the Sendable `work` handle and `raw`. Whichever
        // finishes first wins — so the wall-clock latency is bounded by `timeout`
        // even if `session.respond` ignores cancellation. The losing generation is
        // cancelled in the background.
        let work = Task {
            (try? await session.respond(to: raw))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
        }
        let timeoutNanos = UInt64(timeout * 1_000_000_000)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { await work.value }
            group.addTask { try? await Task.sleep(nanoseconds: timeoutNanos); return nil }
            let first = (await group.next() ?? nil)   // String? : the work's text, or nil on timeout
            group.cancelAll()
            work.cancel()
            return first ?? raw
        }
    }
}
