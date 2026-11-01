import AppKit
import CoreWLAN

func checkSystemStatus() throws {
    precondition(SystemStatusSnapshot.unknown.battery.isPresent)
    precondition(SystemStatusSnapshot.unknown.battery.level == nil)
    precondition(SystemStatusValues.level(nil) == nil)
    precondition(SystemStatusValues.level(.nan) == nil)
    precondition(SystemStatusValues.level(.infinity) == nil)
    precondition(SystemStatusValues.level(-0.2) == 0)
    precondition(SystemStatusValues.level(1.5) == 1)
    precondition(SystemStatusValues.batteryLevel(current: 75, maximum: 100) == 0.75)
    precondition(SystemStatusValues.batteryLevel(current: 0, maximum: 100) == 0)
    precondition(SystemStatusValues.batteryLevel(current: 102, maximum: 100) == 1)
    precondition(SystemStatusValues.batteryLevel(current: -1, maximum: 100) == nil)
    precondition(SystemStatusValues.batteryLevel(current: 80, maximum: 0) == nil)
    precondition(SystemStatusValues.batteryLevel(current: 80, maximum: .infinity) == nil)
    precondition(SystemStatusValues.batteryLevel(current: .nan, maximum: 100) == nil)

    precondition(SystemStatusValues.signalStrength(rssi: 0) == nil)
    precondition(SystemStatusValues.signalStrength(rssi: -128) == nil)
    precondition(SystemStatusValues.signalStrength(rssi: -40) == 3)
    precondition(SystemStatusValues.signalStrength(rssi: -60) == 2)
    precondition(SystemStatusValues.signalStrength(rssi: -75) == 1)
    precondition(SystemStatusValues.signalStrength(rssi: -90) == 0)
    precondition(SystemStatusValues.wifi(powerOn: false, mode: .station, rssi: -40) == .off)
    precondition(SystemStatusValues.wifi(powerOn: true, mode: .none, rssi: 0) == .disconnected)
    precondition(SystemStatusValues.wifi(powerOn: true, mode: .station, rssi: 0) == .connected(strength: nil))
    precondition(SystemStatusValues.wifi(powerOn: true, mode: .station, rssi: -60) == .connected(strength: 2))
    precondition(SystemStatusValues.wifi(powerOn: true, mode: .hostAP, rssi: 0) == .connected(strength: nil))

    precondition(SystemStatusValues.audioLevel(master: nil, channels: []) == nil,
                 "Fixed-volume output devices must not be reported as silent")
    precondition(SystemStatusValues.audioLevel(master: nil, channels: [nil, .nan]) == nil)
    precondition(SystemStatusValues.audioLevel(master: 0.6, channels: [0.1, 0.2]) == 0.6)
    precondition(SystemStatusValues.audioLevel(master: .nan, channels: [0.2, 0.8]) == 0.5)
    precondition(SystemStatusValues.audioLevel(master: nil, channels: [nil, 0.8]) == 0.8)
    precondition(SystemStatusValues.audioLevel(master: 0, channels: [0.8]) == 0)
    precondition(SystemStatusValues.muted(master: true, channels: [false, false]))
    precondition(!SystemStatusValues.muted(master: false, channels: [true, true]))
    precondition(SystemStatusValues.muted(master: nil, channels: [true, true]))
    precondition(!SystemStatusValues.muted(master: nil, channels: [true, false]))
    precondition(!SystemStatusValues.muted(master: nil, channels: [true, nil]))
    precondition(!SystemStatusValues.muted(master: nil, channels: []))
    print("PASS: missing/invalid power and audio readings, channel-volume fallback, mute and permission-free Wi-Fi states")
}

private final class FakeSystemStatusReader: SystemStatusReading {
    var starts = 0
    var stops = 0
    var refreshes = 0
    var deliveries: [(SystemStatusSnapshot) -> Void] = []
    func start(deliver: @escaping (SystemStatusSnapshot) -> Void) {
        starts += 1
        deliveries.append(deliver)
    }
    func stop() { stops += 1 }
    func refresh() { refreshes += 1 }
}

@MainActor
func checkSystemStatusLifecycle() async throws {
    let reader = FakeSystemStatusReader()
    let monitor = SystemStatusMonitor(reader: reader)
    defer { monitor.stop() }
    let first = SystemStatusSnapshot(battery: BatteryStatus(level: 0.8, isCharging: false,
                                                           isPluggedIn: false, isPresent: true),
                                     wifi: .connected(strength: 2), audio: AudioStatus(level: 0.4, isMuted: false))
    let second = SystemStatusSnapshot(battery: BatteryStatus(level: 0.7, isCharging: false,
                                                            isPluggedIn: false, isPresent: true),
                                      wifi: .off, audio: AudioStatus(level: nil, isMuted: false))
    monitor.start()
    monitor.start()
    precondition(reader.starts == 1, "Repeated start must not create duplicate listeners or timers")
    reader.deliveries[0](first)
    try await Task.sleep(for: .milliseconds(20))
    precondition(monitor.snapshot == first)
    monitor.stop()
    monitor.stop()
    precondition(reader.stops == 1)
    reader.deliveries[0](second)
    try await Task.sleep(for: .milliseconds(20))
    precondition(monitor.snapshot == first, "A completion after stop must not publish")
    let refreshes = reader.refreshes
    monitor.refresh()
    precondition(reader.refreshes == refreshes)

    monitor.start()
    precondition(reader.starts == 2)
    reader.deliveries[0](second)
    try await Task.sleep(for: .milliseconds(20))
    precondition(monitor.snapshot == first, "An old session cannot publish after restart")
    reader.deliveries[1](second)
    try await Task.sleep(for: .milliseconds(20))
    precondition(monitor.snapshot == second)
    let center = NSWorkspace.shared.notificationCenter
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(20))
    precondition(reader.stops == 2)
    reader.deliveries[1](first)
    try await Task.sleep(for: .milliseconds(20))
    precondition(monitor.snapshot == second, "Sleep invalidates pending publications")
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(20))
    precondition(reader.starts == 3, "Duplicate wake notifications must not multiply readers")
    monitor.stop()
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(20))
    precondition(reader.starts == 3, "A stopped monitor must not restart on wake")
    print("PASS: status monitor idempotent start/stop, stale callback rejection, sleep and wake")
}
