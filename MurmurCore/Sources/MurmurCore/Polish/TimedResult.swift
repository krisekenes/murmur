import Foundation

/// Returns the first result without waiting for work that ignores cancellation.
public func timedResult<Value: Sendable>(
    of work: Task<Value, Never>, timeout: Duration, fallback: Value
) async -> Value {
    let (stream, continuation) = AsyncStream<Value>.makeStream()
    let waiter = Task {
        continuation.yield(await work.value)
        continuation.finish()
    }
    let timer = Task {
        do { try await Task.sleep(for: timeout) } catch { return }
        continuation.yield(fallback)
        continuation.finish()
    }
    defer {
        continuation.finish()
        waiter.cancel()
        timer.cancel()
        work.cancel()
    }
    for await value in stream { return value }
    return fallback
}
