import AppKit
import SwiftUI

public final class OverlayPanel: NSPanel {
    public init<Content: View>(content: Content) {
        super.init(contentRect: NSRect(origin: .zero, size: Theme.pillSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: content)
        positionBottomCenter()
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - Theme.pillSize.width / 2, y: f.minY + 80))
    }
}
