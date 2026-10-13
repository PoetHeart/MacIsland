import AppKit

/// A visual hint only: never activates or participates in the original window's drag.
@MainActor
final class WindowPreviewController {
    private(set) var panel: IslandPanel?
    private var targetFrame: CGRect?

    func show(frame: CGRect, animated: Bool) {
        guard frame.width > 0, frame.height > 0 else { hide(); return }
        if panel == nil {
            let overlay = IslandPanel(frame: frame)
            overlay.level = .floating
            overlay.contentView = WindowPreviewView()
            overlay.setAccessibilityElement(false)
            panel = overlay
        }
        guard let panel else { return }
        guard targetFrame != frame || !panel.isVisible else { return }
        let wasVisible = panel.isVisible
        targetFrame = frame
        if wasVisible && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        if !wasVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
        targetFrame = nil
    }
}

private final class WindowPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // Keep the outer edge at the requested bounds, including odd-sized split areas.
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
