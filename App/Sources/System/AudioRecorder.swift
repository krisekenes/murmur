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
