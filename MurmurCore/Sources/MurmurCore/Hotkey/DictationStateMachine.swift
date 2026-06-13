import Foundation

public enum HotkeyMode: Equatable, Sendable { case hold, locked }
public enum HotkeyEvent: Equatable, Sendable { case keyDown, keyUp, escape, timeout }

public enum DictationEffect: Equatable, Sendable {
    case startRecording
    case finishRecording
    case cancelRecording
    /// Reserved contract case: the machine signals double-tap timing via
    /// `pendingTimeout` rather than returning this. Kept for the documented effect set.
    case scheduleTimeout(after: TimeInterval)
    case none
}

public struct DictationTuning: Sendable {
    public var tapMaxDuration: TimeInterval = 0.25
    public var doubleTapWindow: TimeInterval = 0.30
    public var minPolishWords: Int = 4
    public init() {}
}

public final class DictationStateMachine {
    public enum State: Equatable, Sendable {
        case idle
        case recording(HotkeyMode)
        case awaitingSecondTap
    }

    public private(set) var state: State = .idle

    private let tuning: DictationTuning
    private var keyDownAt: TimeInterval = 0
    private var firstTapReleasedAt: TimeInterval = 0

    public init(tuning: DictationTuning = DictationTuning()) { self.tuning = tuning }

    @discardableResult
    public func handle(_ event: HotkeyEvent, at now: TimeInterval) -> DictationEffect {
        transition(event, now)
    }

    private func transition(_ event: HotkeyEvent, _ now: TimeInterval) -> DictationEffect {
        switch (state, event) {
        case (.idle, .keyDown):
            keyDownAt = now
            state = .recording(.hold)
            return .startRecording

        case (.recording(.hold), .keyUp):
            let heldFor = now - keyDownAt
            if heldFor >= tuning.tapMaxDuration {
                state = .idle
                return .finishRecording
            }
            firstTapReleasedAt = now
            state = .awaitingSecondTap
            return .cancelRecording

        case (.recording(.hold), .escape):
            state = .idle
            return .cancelRecording

        case (.awaitingSecondTap, .keyDown):
            if now - firstTapReleasedAt <= tuning.doubleTapWindow {
                state = .recording(.locked)
                return .startRecording
            }
            keyDownAt = now
            state = .recording(.hold)
            return .startRecording

        case (.awaitingSecondTap, .timeout), (.awaitingSecondTap, .escape):
            state = .idle
            return .none

        case (.recording(.locked), .keyDown):
            state = .idle
            return .finishRecording

        case (.recording(.locked), .escape):
            state = .idle
            return .cancelRecording

        default:
            return .none
        }
    }
}

extension DictationStateMachine {
    /// If a double-tap window just opened, returns the delay to arm a one-shot
    /// timer that will feed `.timeout` back into `handle(_:at:)`.
    public var pendingTimeout: TimeInterval? {
        state == .awaitingSecondTap ? tuning.doubleTapWindow : nil
    }
}
