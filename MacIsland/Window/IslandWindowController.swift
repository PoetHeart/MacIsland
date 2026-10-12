import AppKit
import SwiftUI

@MainActor
final class IslandWindowController {
    private(set) var panel: IslandPanel?
    private(set) var model: IslandModel?
    private var pointerTimer: Timer?
    private var transition: Task<Void, Never>?
    private(set) var displaySize: CGSize = .zero
    private var pointerInside = false
    private var isVisible = false

    private let pointerLocation: () -> CGPoint

    init(pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func show() {
        isVisible = true
        rebuildWindow()
    }

    func hide() {
        isVisible = false
        stopTracking()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func rebuildWindow() {
        stopTracking()
        panel?.orderOut(nil)
        guard isVisible, let screen = ScreenGeometry.preferredScreen() else { return }
        let geometry = ScreenGeometry(screen: screen)
        let model = IslandModel(geometry: geometry)
        let panel = IslandPanel(frame: geometry.panelFrame)
        self.model = model
        self.panel = panel
        displaySize = geometry.size(for: .idle)
        let view = IslandView(model: model) { [weak self] size in
            self?.displaySize = size
        }
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        startTracking()
    }

    private func startTracking() {
        // One cheap point-in-path check per tick. No event tap, Accessibility permission, or global keyboard monitor.
        let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(checkPointer), userInfo: nil, repeats: true)
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        checkPointer()
    }

    private func stopTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        transition?.cancel()
        transition = nil
        pointerInside = false
    }

    @objc private func checkPointer() {
        guard isVisible, let panel, let model else { return }
        let mouse = pointerLocation()
        let local = CGPoint(x: mouse.x - (model.geometry.centerX - displaySize.width / 2), y: model.geometry.top - mouse.y)
        let inside = IslandOutline().path(in: CGRect(origin: .zero, size: displaySize)).contains(local)
        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        transition?.cancel()
        transition = Task { [weak self] in
            guard let self, let model = self.model else { return }
            do {
                if inside {
                    model.state = .compact
                    try await Task.sleep(for: .milliseconds(180))
                    model.state = .expanded
                } else {
                    // Debounce the edge so the spring and small pointer movements cannot flicker.
                    try await Task.sleep(for: .milliseconds(150))
                    model.state = .compact
                    try await Task.sleep(for: .milliseconds(180))
                    model.state = .idle
                }
            } catch { /* Re-entry, hiding, or display changes cancel the pending transition. */ }
        }
    }

    @objc private func screensChanged() { if isVisible { rebuildWindow() } }
    @objc private func willSleep() {
        stopTracking()
        panel?.orderOut(nil)
    }
    @objc private func didWake() { if isVisible { rebuildWindow() } }
}
