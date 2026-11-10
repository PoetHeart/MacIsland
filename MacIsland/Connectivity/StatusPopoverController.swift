import AppKit
import SwiftUI

/// Owns the transient panel; hardware controllers outlive individual presentations.
@MainActor
final class StatusPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let settings: IslandSettings
    private let status: SystemStatusMonitor
    private let wifi: WiFiController
    private let bluetooth: BluetoothController
    private let openSettings: () -> Void
    private var closeMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []

    var isShown: Bool { popover.isShown }

    init(settings: IslandSettings, status: SystemStatusMonitor,
         wifi: WiFiController? = nil, bluetooth: BluetoothController? = nil,
         openSettings: @escaping () -> Void) {
        self.settings = settings
        self.status = status
        self.wifi = wifi ?? WiFiController()
        self.bluetooth = bluetooth ?? BluetoothController()
        self.openSettings = openSettings
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { close(); return }
        show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !popover.isShown else { return }
        let height = Self.availableHeight(on: button.window?.screen)
        let content = ConnectivityPanelView(settings: settings, status: status, wifi: wifi, bluetooth: bluetooth,
            openSettings: { [weak self] in self?.close(); self?.openSettings() },
            openSystemSettings: { [weak self] destination in
                self?.close()
                Self.openSystemSettings(destination)
            })
            .frame(width: 360)
            .frame(maxHeight: height)
            .background(ConnectivityPanelMaterial())
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.animates = settings.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        guard popover.isShown else { return }
        wifi.start()
        bluetooth.start()
        status.refresh()
        guard closeMonitor == nil else { return }
        // The panel's Escape binding works even when a control currently has keyboard focus.
        closeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self, self.popover.isShown else { return false }
                self.close()
                return true
            }
            return handled ? nil : event
        }
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        if let closeMonitor { NSEvent.removeMonitor(closeMonitor) }
        closeMonitor = nil
        wifi.stop()
        bluetooth.stop()
    }

    func shutdown() {
        close()
        if let closeMonitor { NSEvent.removeMonitor(closeMonitor) }
        closeMonitor = nil
        wifi.stop()
        bluetooth.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    static func availableHeight(on screen: NSScreen?) -> CGFloat {
        max(240, min(600, (screen?.visibleFrame.height ?? 700) - 64))
    }

    static func openSystemSettings(_ destination: ConnectivitySettingsDestination) {
        guard let url = URL(string: settingsURL(for: destination)) else { return }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func settingsURL(for destination: ConnectivitySettingsDestination) -> String {
        switch destination {
        case .wifi: return "x-apple.systempreferences:com.apple.wifi-settings-extension"
        case .bluetooth: return "x-apple.systempreferences:com.apple.BluetoothSettings"
        case .locationPrivacy: return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .bluetoothPrivacy: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        }
    }

    deinit {
        if let closeMonitor { NSEvent.removeMonitor(closeMonitor) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}

private struct ConnectivityPanelMaterial: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 24
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .withinWindow
        material.state = .active
        return material
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.wantsLayer = true
        view.layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
        if let material = view as? NSVisualEffectView { material.state = reduceTransparency ? .inactive : .active }
    }
}
