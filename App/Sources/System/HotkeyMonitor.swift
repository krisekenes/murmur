import AppKit
import CoreGraphics
import MurmurCore

@MainActor
public protocol HotkeyMonitorDelegate: AnyObject {
    func hotkeyDidEmit(_ effect: DictationEffect, mode: HotkeyMode?)
}

public enum HotkeyChoice: String, CaseIterable, Sendable {
    case fn          // the Globe/Fn key
    case rightOption
}

/// All mutable state is touched only from the main run loop: `start()` is called
/// on the main actor, so the tap's run-loop source and its callback both run on
/// the main thread. Marked `@unchecked Sendable` so the C callback trampoline can
/// hold an `Unmanaged` pointer to it under Swift 6 strict concurrency.
public final class HotkeyMonitor: @unchecked Sendable {
    public weak var delegate: HotkeyMonitorDelegate?

    private let machine: DictationStateMachine
    private let choice: HotkeyChoice
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyDown = false
    private var doubleTapTimer: Timer?
    private var watchdog: Timer?

    public init(choice: HotkeyChoice, machine: DictationStateMachine = DictationStateMachine()) {
        self.choice = choice
        self.machine = machine
    }

    public func stop() {
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        delegate = nil
    }

    deinit { stop() }

    @MainActor public func start() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap else {
            NSLog("Murmur: failed to create event tap — check Accessibility + Input Monitoring permissions")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        startWatchdog()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime

        // Esc anywhere cancels.
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            emit(machine.handle(.escape, at: now)); return
        }

        switch choice {
        case .fn:
            guard type == .flagsChanged else { return }
            let down = event.flags.contains(.maskSecondaryFn)
            guard down != isHotkeyDown else { return }   // dedupe; Fn flag bleeds into other keys
            isHotkeyDown = down
            emit(machine.handle(down ? .keyDown : .keyUp, at: now))
        case .rightOption:
            guard type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == 61 else { return } // kVK_RightOption
            let down = event.flags.contains(.maskAlternate)
            guard down != isHotkeyDown else { return }
            isHotkeyDown = down
            emit(machine.handle(down ? .keyDown : .keyUp, at: now))
        }
    }

    private func emit(_ effect: DictationEffect) {
        // Arm the double-tap timer when a window opens.
        doubleTapTimer?.invalidate()
        // .timeout always moves the machine to .idle (pendingTimeout becomes nil), so this never self-arms forever.
        if let delay = machine.pendingTimeout {
            doubleTapTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.emit(self.machine.handle(.timeout, at: ProcessInfo.processInfo.systemUptime))
            }
        }
        guard effect != .none else { return }
        // Read synchronously now: the machine state reflects the just-applied transition.
        let mode = machine.recordingMode
        Task { @MainActor in self.delegate?.hotkeyDidEmit(effect, mode: mode) }  // statically main-isolated; satisfies @MainActor delegate
    }

    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        }
    }
}
