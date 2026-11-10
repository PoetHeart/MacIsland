import AppKit

private actor PanelWiFiOperations: WiFiPanelOperating {
    func read(includeName: Bool) async -> WiFiPanelReading { WiFiPanelReading(power: true, name: nil) }
    func setPower(_ enabled: Bool) async -> WiFiPowerResult { fatalError("Popover smoke test must never change Wi-Fi") }
}
@MainActor private final class PanelNameAuthorization: WiFiNameAuthorizing {
    var onChange: (() -> Void)?
    var access: WiFiNameAccess { .notRequested }
    func request() { fatalError("Opening a popover must not request location access") }
}
@MainActor private final class PanelBluetoothRadio: BluetoothRadioReading {
    var authorization: BluetoothAccess { .notRequested }
    var isPoweredOn: Bool? { nil }
    func observe(request: Bool, onChange: @escaping () -> Void) {
        precondition(!request, "Opening a popover must not request Bluetooth access")
    }
    func stop() {}
}
private final class PanelPairedDevices: PairedBluetoothReading {
    func paired() -> [BluetoothDeviceItem] { fatalError("Unapproved Bluetooth devices must not be read") }
    func write(connected: Bool, id: String) -> BluetoothWriteResult { fatalError("Popover smoke test must not control devices") }
}

@MainActor
func checkConnectivityPopover() async throws {
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    let nameAuth = PanelNameAuthorization()
    let wifi = WiFiController(operations: PanelWiFiOperations(), authorization: nameAuth)
    let bluetooth = BluetoothController(radio: PanelBluetoothRadio(), reader: PanelPairedDevices())
    let suite = "MacIsland.PanelSmoke.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = IslandSettings(defaults: defaults)
    settings.animationsEnabled = false
    let status = SystemStatusMonitor()
    let controller = StatusPopoverController(settings: settings, status: status, wifi: wifi, bluetooth: bluetooth,
                                             openSettings: {})
    let item = NSStatusBar.system.statusItem(withLength: 30)
    defer {
        controller.shutdown()
        NSStatusBar.system.removeStatusItem(item)
    }
    guard let button = item.button else { fatalError("No status button") }
    button.image = StatusIconRenderer.image(for: .unknown)
    try await Task.sleep(for: .milliseconds(100))
    controller.show(relativeTo: button)
    try await Task.sleep(for: .milliseconds(200))
    precondition(controller.isShown, "The native connections panel must open")
    precondition(wifi.isPowerOn == true && wifi.nameAccess == .notRequested)
    precondition(bluetooth.authorization == .notRequested)
    controller.close()
    for _ in 0..<20 {
        if !controller.isShown { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    precondition(!controller.isShown, "The native panel must close")
    controller.show(relativeTo: button)
    try await Task.sleep(for: .milliseconds(200))
    precondition(controller.isShown, "A dismissed native panel must reopen")
    controller.close()
    print("PASS: native material popover opens, closes and reopens without requesting connectivity permissions")
}
