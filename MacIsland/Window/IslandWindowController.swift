import AppKit
import SwiftUI
import Combine

@MainActor
final class IslandWindowController {
    private(set) var panel: IslandPanel?
    private(set) var model: IslandModel?
    private var pointerTimer: Timer?
    private var transition: Task<Void, Never>?
    private(set) var displaySize: CGSize = .zero
    private var pointerInside = false
    private var isVisible = false
    private var isSleeping = false
    private var generation = UUID()
    private let settings: IslandSettings
    private let windowActions = WindowActionManager()
    private var settingsSubscription: AnyCancellable?

    private let pointerLocation: () -> CGPoint

    init(settings: IslandSettings, pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.settings = settings
        self.pointerLocation = pointerLocation
        settingsSubscription = settings.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func applySettings() {
        isVisible = settings.isVisible
        rebuildWindow()
    }

    func requestWindowControlPermission() { windowActions.requestPermission() }

    func show() {
        if !settings.isVisible { settings.isVisible = true }
        isVisible = true
        rebuildWindow()
    }

    func hide() {
        if settings.isVisible { settings.isVisible = false }
        isVisible = false
        stopTracking()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func rebuildWindow() {
        stopTracking()
        panel?.orderOut(nil)
        generation = UUID()
        guard isVisible, !isSleeping, let screen = DisplayCatalog.screen(for: settings.displaySelection) else { return }
        let geometry = ScreenGeometry(screen: screen)
        let model = IslandModel(geometry: geometry, animationsEnabled: settings.animationsEnabled)
        let panel = IslandPanel(frame: geometry.panelFrame)
        self.model = model
        self.panel = panel
        displaySize = geometry.size(for: .idle)
        let currentGeneration = generation
        let view = IslandView(model: model, windowActions: windowActions) { [weak self] size in
            guard let self, self.generation == currentGeneration else { return }
            self.displaySize = size
        }
        panel.contentView = IslandHostingView(rootView: view)
        panel.orderFrontRegardless()
        startTracking()
    }

    private func startTracking() {
        guard settings.hoverEnabled else { return }
        // One cheap point-in-path check per tick. No event tap, Accessibility permission, or global keyboard monitor.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
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
        guard isVisible, !isSleeping, let panel, let model else { return }
        guard settings.hoverEnabled else {
            panel.ignoresMouseEvents = true
            return
        }
        let mouse = pointerLocation()
        let local = CGPoint(x: mouse.x - (model.geometry.centerX - displaySize.width / 2), y: model.geometry.top - mouse.y)
        let onSurface = model.state != .idle
            && IslandOutline().path(in: CGRect(origin: .zero, size: displaySize)).contains(local)
        let inside = model.geometry.activationRect.contains(mouse) || onSurface
        // The invisible trigger observes the pointer but never blocks clicks underneath.
        panel.ignoresMouseEvents = !onSurface
        guard inside != pointerInside else { return }
        pointerInside = inside
        transition?.cancel()
        transition = Task { [weak self] in
            guard let self, let model = self.model else { return }
            do {
                if inside {
                    self.windowActions.captureTarget()
                    // Re-entering an expanded island cancels collapse without shrinking it first.
                    if model.state != .expanded {
                        model.state = .compact
                        try await Task.sleep(for: .seconds(self.settings.effectiveHoverDelay))
                        model.state = .expanded
                    }
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
        isSleeping = true
        stopTracking()
        panel?.orderOut(nil)
    }
    @objc private func didWake() {
        isSleeping = false
        if isVisible { rebuildWindow() }
    }

    func shutdown() {
        stopTracking()
        settingsSubscription = nil
        panel?.orderOut(nil)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        pointerTimer?.invalidate()
        transition?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
