import AppKit
import ApplicationServices
import MurmurCore

public enum InsertOutcome: Sendable { case pasted, axInserted, leftOnClipboard }

public final class TextInserter {
    public init() {}

    @discardableResult
    public func insert(_ text: String) -> InsertOutcome {
        if axInsert(text) { return .axInserted }      // try direct insert first; no clipboard churn
        if paste(text) { return .pasted }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .leftOnClipboard
    }

    // MARK: - Synthetic paste with ownership-guarded restore
    private func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { dict[type] = d } }
            return dict
        } ?? []

        pb.clearContents()
        pb.setString(text, forType: .string)
        let decision = PasteDecision(ownedChangeCount: pb.changeCount)

        guard postCommandV() else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard decision.shouldRestore(currentChangeCount: pb.changeCount) else { return }
            pb.clearContents()
            for dict in saved {
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                pb.writeObjects([item])
            }
        }
        return true
    }

    private func postCommandV() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)   // 'v'
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
        return vDown != nil && vUp != nil
    }

    // MARK: - Accessibility direct insertion
    private func axInsert(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return false }
        let el = element as! AXUIElement
        // Only safe for elements that expose a settable value/selected-text.
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }
}
