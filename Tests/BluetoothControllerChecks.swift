import AppKit

@MainActor
private final class FakeBluetoothRadio: BluetoothRadioReading {
    var authorization: BluetoothAccess = .notRequested
    var isPoweredOn: Bool?
    private(set) var requests = 0
    private(set) var stops = 0
    var changed: (() -> Void)?
    func observe(request: Bool, onChange: @escaping () -> Void) {
        if request && authorization == .notRequested { requests += 1 }
        changed = onChange
    }
    func stop() { changed = nil; stops += 1 }
    func simulate(_ access: BluetoothAccess, powered: Bool?) {
        authorization = access
        isPoweredOn = powered
        changed?()
    }
}

private final class FakePairedBluetooth: PairedBluetoothReading, @unchecked Sendable {
    enum WriteBehavior { case apply, acceptWithoutChange, fail, failedButActualChanged }
    private let lock = NSLock()
    private var rows: [BluetoothDeviceItem] = []
    private var behavior: WriteBehavior = .apply
    private var gate: DispatchSemaphore?
    private var counts = (reads: 0, writes: 0)

    func replace(_ rows: [BluetoothDeviceItem], behavior: WriteBehavior = .apply, gate: DispatchSemaphore? = nil) {
        lock.withLock {
            self.rows = rows
            self.behavior = behavior
            self.gate = gate
        }
    }
    func metrics() -> (reads: Int, writes: Int) { lock.withLock { counts } }

    func paired() -> [BluetoothDeviceItem] {
        lock.withLock { counts.reads += 1; return rows }
    }
    func write(connected: Bool, id: String) -> BluetoothWriteResult {
        let semaphore = lock.withLock { counts.writes += 1; return gate }
        if let semaphore, semaphore.wait(timeout: .now() + 4) != .success { return .failed }
        return lock.withLock {
            guard let idx = rows.firstIndex(where: { $0.id == id }) else { return .missing }
            guard rows[idx].canControl else { return .unsupported }
            if behavior == .fail { return .failed }
            if behavior == .apply || behavior == .failedButActualChanged {
                let row = rows[idx]
                rows[idx] = BluetoothDeviceItem(id: id, name: row.name, kind: row.kind,
                                                isConnected: connected, canControl: row.canControl)
            }
            return behavior == .failedButActualChanged ? .failed : .accepted
        }
    }
}

@MainActor
private func waitForBluetoothCheck(_ condition: @escaping () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "BluetoothControllerChecks", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for a simulated Bluetooth event"])
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
func checkBluetoothController() async throws {
    let radio = FakeBluetoothRadio()
    let backend = FakePairedBluetooth()
    let controller = BluetoothController(radio: radio, reader: backend, verifyDelay: 0)
    let mouse = BluetoothDeviceItem(id: "AA", name: "Same name", kind: .mouse, isConnected: false, canControl: true)
    let le = BluetoothDeviceItem(id: "BB", name: "Same name", kind: .other, isConnected: true, canControl: false)
    backend.replace([mouse, le])
    controller.start()
    controller.start()
    controller.refresh()
    precondition(radio.requests == 0 && backend.metrics().reads == 0, "Passive open cannot prompt or read devices")
    controller.requestAccess()
    precondition(radio.requests == 1)
    for denied in [BluetoothAccess.denied, .restricted, .unavailable] {
        radio.simulate(denied, powered: nil)
        precondition(controller.authorization == denied && controller.devices.isEmpty && backend.metrics().reads == 0)
        controller.setConnected(true, for: mouse.id)
        precondition(controller.message == "蓝牙不可用" && backend.metrics().writes == 0)
    }
    radio.simulate(.allowed, powered: false)
    controller.refresh()
    precondition(controller.isPoweredOn == false && backend.metrics().reads == 0)
    radio.simulate(.allowed, powered: true)
    try await waitForBluetoothCheck { controller.devices == [mouse, le] }
    controller.setConnected(false, for: le.id)
    precondition(controller.message == "请在系统蓝牙设置中管理此设备" && backend.metrics().writes == 0)
    controller.setConnected(true, for: "absent")
    precondition(controller.message == "设备已不在配对列表中" && backend.metrics().writes == 0)

    // The row looked valid at selection time. Another app has unpaired it since.
    backend.replace([le])
    controller.setConnected(true, for: mouse.id)
    try await waitForBluetoothCheck { controller.busyDeviceID == nil }
    precondition(backend.metrics().writes == 0 && controller.message == "设备已不在配对列表中")
    precondition(controller.devices == [le], "A stale address must not fall back to a name match")

    backend.replace([mouse, le], behavior: .acceptWithoutChange)
    controller.refresh()
    try await waitForBluetoothCheck { controller.devices == [mouse, le] }
    controller.setConnected(true, for: mouse.id)
    try await waitForBluetoothCheck { controller.busyDeviceID == nil }
    precondition(controller.message == "未能确认设备连接状态" && !controller.devices[0].isConnected)
    backend.replace([mouse, le], behavior: .fail)
    controller.setConnected(true, for: mouse.id)
    try await waitForBluetoothCheck { controller.busyDeviceID == nil }
    precondition(controller.message == "蓝牙连接失败" && !controller.devices[0].isConnected)
    backend.replace([mouse, le], behavior: .failedButActualChanged)
    controller.setConnected(true, for: mouse.id)
    try await waitForBluetoothCheck { controller.busyDeviceID == nil }
    precondition(controller.message == "设备已连接" && controller.devices[0].isConnected,
                 "A concurrent connection verified by address overrides an already-connected error")

    // Close the panel while the request is running, then complete it without any actual hardware.
    let gate = DispatchSemaphore(value: 0)
    backend.replace([mouse, le], gate: gate)
    let initialWrites = backend.metrics().writes
    controller.setConnected(true, for: mouse.id)
    try await waitForBluetoothCheck { backend.metrics().writes > initialWrites }
    controller.setConnected(true, for: mouse.id)
    controller.setConnected(false, for: le.id)
    controller.stop()
    precondition(controller.busyDeviceID == mouse.id)
    gate.signal()
    try await waitForBluetoothCheck { controller.busyDeviceID == nil }
    precondition(backend.metrics().writes == initialWrites + 1)
    precondition(controller.message == "设备已连接" && controller.devices[0].isConnected)
    let reads = backend.metrics().reads
    controller.refresh()
    precondition(backend.metrics().reads == reads)

    controller.start()
    try await waitForBluetoothCheck { !controller.isLoading }
    precondition(controller.message == "设备已连接", "A result completed while closed should be shown on reopen")
    let reopenGate = DispatchSemaphore(value: 0)
    backend.replace(controller.devices, gate: reopenGate)
    controller.setConnected(false, for: mouse.id)
    try await waitForBluetoothCheck { backend.metrics().writes == initialWrites + 2 }
    controller.stop()
    radio.simulate(.allowed, powered: nil)
    controller.start()
    precondition(controller.isPoweredOn == nil && controller.busyDeviceID == mouse.id)
    reopenGate.signal()
    try await waitForBluetoothCheck { controller.busyDeviceID == nil }
    precondition(controller.message == "设备已断开" && !controller.devices[0].isConnected)
    controller.refresh()
    precondition(controller.devices == [mouse, le], "Pending radio initialization must retain the verified snapshot")
    radio.simulate(.allowed, powered: true)
    try await waitForBluetoothCheck { !controller.isLoading }
    controller.stop()
    precondition(controller.message == nil, "A result already shown should not survive the next close")
    controller.start()
    try await waitForBluetoothCheck { !controller.isLoading }
    precondition(controller.message == nil)
    let center = NSWorkspace.shared.notificationCenter
    let stops = radio.stops
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await waitForBluetoothCheck { radio.stops > stops }
    let sleepingReads = backend.metrics().reads
    controller.refresh()
    precondition(backend.metrics().reads == sleepingReads)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await waitForBluetoothCheck { backend.metrics().reads > sleepingReads && !controller.isLoading }
    radio.simulate(.denied, powered: nil)
    precondition(controller.devices.isEmpty && controller.authorization == .denied)
    controller.stop()

    precondition(BluetoothDeviceKind.classify(name: "Magic Trackpad", major: 5, minor: 0x20) == .trackpad)
    precondition(BluetoothDeviceKind.classify(name: "HID", major: 5, minor: 0x30) == .keyboard)
    precondition(BluetoothDeviceKind.classify(name: "HID", major: 5, minor: 0x02) == .controller)
    precondition(BluetoothDeviceKind.classify(name: "Audio", major: 4, minor: 6) == .headphones)
    precondition(BluetoothDeviceKind.mouse.isInputDevice && BluetoothDeviceKind.keyboard.isInputDevice)
    precondition(BluetoothDeviceKind.trackpad.isInputDevice && BluetoothDeviceKind.other.isInputDevice)
    precondition(!BluetoothDeviceKind.headphones.isInputDevice)
    print("PASS: Bluetooth permission gating, stable addresses, unsupported devices, verified baseband actions, panel closure and sleep")
}
