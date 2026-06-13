import XCTest
@testable import MurmurCore

final class DictationStateMachineTests: XCTestCase {
    private func machine() -> DictationStateMachine { DictationStateMachine(tuning: DictationTuning()) }

    func test_holdThenRelease_transcribes() {
        let m = machine()
        XCTAssertEqual(m.handle(.keyDown, at: 0.0), .startRecording)
        XCTAssertEqual(m.handle(.keyUp, at: 0.5), .finishRecording)
        XCTAssertEqual(m.state, .idle)
    }

    func test_escapeWhileHolding_cancels() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        XCTAssertEqual(m.handle(.escape, at: 0.2), .cancelRecording)
        XCTAssertEqual(m.state, .idle)
    }

    func test_quickTap_armsDoubleTapWindowAndDiscards() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        XCTAssertEqual(m.handle(.keyUp, at: 0.1), .cancelRecording)
        XCTAssertEqual(m.pendingTimeout, 0.30)   // controller arms a one-shot timer off this
    }

    func test_doubleTap_entersLockedRecording_andTapStops() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)                 // first tap (discard + open window)
        XCTAssertEqual(m.handle(.keyDown, at: 0.25), .startRecording) // second tap within window => lock
        XCTAssertEqual(m.handle(.keyUp, at: 0.30), .none)            // ignore the arming tap's release
        XCTAssertEqual(m.state, .recording(.locked))
        XCTAssertEqual(m.handle(.keyDown, at: 5.0), .finishRecording) // a later tap stops + transcribes
        XCTAssertEqual(m.state, .idle)
    }

    func test_singleTapTimesOut_toIdle_noEffect() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        XCTAssertEqual(m.handle(.timeout, at: 0.45), DictationEffect.none)
        XCTAssertEqual(m.state, .idle)
    }

    func test_secondTapAfterWindow_isTreatedAsFreshHold() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        _ = m.handle(.timeout, at: 0.45)             // window closed -> idle
        XCTAssertEqual(m.handle(.keyDown, at: 0.50), .startRecording)
        XCTAssertEqual(m.state, .recording(.hold))
    }

    func test_escapeWhileLocked_cancels() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        _ = m.handle(.keyDown, at: 0.25)
        _ = m.handle(.keyUp, at: 0.30)
        XCTAssertEqual(m.handle(.escape, at: 1.0), .cancelRecording)
        XCTAssertEqual(m.state, .idle)
    }

    func test_recordingMode_reflectsState() {
        let m = machine()
        XCTAssertNil(m.recordingMode)
        _ = m.handle(.keyDown, at: 0.0)
        XCTAssertEqual(m.recordingMode, .hold)
        _ = m.handle(.keyUp, at: 0.1)
        _ = m.handle(.keyDown, at: 0.25)
        XCTAssertEqual(m.recordingMode, .locked)
    }

    func test_lockedRecording_stopsOnKeyDown_evenIfArmingKeyUpMissing() {
        let m = machine()
        _ = m.handle(.keyDown, at: 0.0)
        _ = m.handle(.keyUp, at: 0.1)
        _ = m.handle(.keyDown, at: 0.25)          // double-tap => locked
        XCTAssertEqual(m.state, .recording(.locked))
        // The arming tap's keyUp never arrives; the user taps to stop.
        XCTAssertEqual(m.handle(.keyDown, at: 5.0), .finishRecording)
        XCTAssertEqual(m.state, .idle)
    }
}
