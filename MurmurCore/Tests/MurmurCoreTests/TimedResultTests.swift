import XCTest
@testable import MurmurCore

final class TimedResultTests: XCTestCase {
    func testReturnsCompletedWork() async {
        let work = Task { "polished" }
        let result = await timedResult(of: work, timeout: .seconds(1), fallback: "raw")
        XCTAssertEqual(result, "polished")
    }

    func testTimeoutDoesNotWaitForUncooperativeWork() async {
        let work = Task {
            // An unstructured task does not inherit the waiter's cancellation.
            await Task.detached {
                try? await Task.sleep(for: .seconds(1))
                return "late"
            }.value
        }
        let start = ContinuousClock.now
        let result = await timedResult(of: work, timeout: .milliseconds(10), fallback: "raw")
        XCTAssertEqual(result, "raw")
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        _ = await work.value
    }
}
