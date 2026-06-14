import AVFoundation
import FluidAudio
import os

/// Captures mic audio to an in-memory 16kHz mono buffer (never written to disk).
/// `samples` is guarded by a lock because the AVAudioEngine tap callback runs on a
/// real-time audio thread while the accessors are called from the main actor.
public final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let converter = AudioConverter()    // default target: 16kHz mono Float32
    private let lock = OSAllocatedUnfairLock(initialState: [Float]())
    private var isRunning = false

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        lock.withLock { $0.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if let converted = try? self.converter.resampleBuffer(buffer) {
                self.lock.withLock { $0.append(contentsOf: converted) }
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
        return lock.withLock { $0 }
    }

    /// Discards in-flight audio (cancel path).
    public func cancel() {
        _ = stop()
        lock.withLock { $0.removeAll(keepingCapacity: false) }
    }

    /// Smoothed recent input level (0...1) for the overlay meter: RMS over the last ~64ms.
    public var currentLevel: Float {
        let window = lock.withLock { Array($0.suffix(1024)) }
        guard !window.isEmpty else { return 0 }
        let sumSq = window.reduce(Float(0)) { $0 + $1 * $1 }
        return min(1, (sumSq / Float(window.count)).squareRoot())
    }
}
