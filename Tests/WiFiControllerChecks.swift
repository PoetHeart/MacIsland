import AppKit

private actor FakeWiFiHardware: WiFiPanelOperating {
    private(set) var power: Bool?
    private(set) var reads: [Bool] = []
    private(set) var writes: [Bool] = []
    private var holdNextRead = false
    private var pendingRead: CheckedContinuation<WiFiPanelReading, Never>?
    private var pendingWrite: CheckedContinuation<WiFiPowerResult, Never>?

    init(power: Bool?) { self.power = power }

    func read(includeName: Bool) async -> WiFiPanelReading {
        reads.append(includeName)
        if holdNextRead {
            holdNextRead = false
            return await withCheckedContinuation { pendingRead = $0 }
        }
        return WiFiPanelReading(power: power, name: includeName && power == true ? "Example network" : nil)
    }

    func setPower(_ enabled: Bool) async -> WiFiPowerResult {
        writes.append(enabled)
        return await withCheckedContinuation { pendingWrite = $0 }
    }

    func finishWrite(actual: Bool?, accepted: Bool) {
        power = actual
        precondition(pendingWrite != nil)
        pendingWrite?.resume(returning: WiFiPowerResult(actual: actual, accepted: accepted))
        pendingWrite = nil
    }

    func delayNextRead() { holdNextRead = true }
    func finishStaleRead() {
        precondition(pendingRead != nil)
        pendingRead?.resume(returning: WiFiPanelReading(power: false, name: "Stale"))
        pendingRead = nil
    }

    var hasPendingRead: Bool { pendingRead != nil }
    var hasPendingWrite: Bool { pendingWrite != nil }
}

@MainActor
private final class FakeWiFiAuthorization: WiFiNameAuthorizing {
    var onChange: (() -> Void)?
    var value: WiFiNameAccess
    private(set) var queries = 0
    private(set) var requests = 0
    init(_ value: WiFiNameAccess) { self.value = value }
    var access: WiFiNameAccess { queries += 1; return value }
    func request() { requests += 1 }
    func change(to value: WiFiNameAccess) { self.value = value; onChange?() }
}

@MainActor
func checkWiFiController() async throws {
    func wait(_ condition: @escaping @MainActor () async -> Bool, _ label: String) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure(label)
    }

    let missing = FakeWiFiHardware(power: nil)
    let missingController = WiFiController(operations: missing, authorization: FakeWiFiAuthorization(.authorized))
    missingController.start()
    try await wait({ await missing.reads.count == 1 }, "No-interface read did not start")
    precondition(missingController.isPowerOn == nil)
    missingController.setPower(true)
    precondition(missingController.message == "未找到 Wi-Fi 接口" && !missingController.isBusy)
    let missingWrites = await missing.writes
    precondition(missingWrites.isEmpty)
    missingController.stop()

    let hardware = FakeWiFiHardware(power: true)
    let auth = FakeWiFiAuthorization(.notRequested)
    let wifi = WiFiController(operations: hardware, authorization: auth)
    defer { wifi.stop() }
    wifi.start()
    wifi.start()
    try await wait({ wifi.isPowerOn == true }, "Panel did not show the measured power state")
    let initialReads = await hardware.reads
    precondition(initialReads == [false] && auth.queries == 0 && auth.requests == 0,
                 "Opening the panel must not even query location permission or read SSID")
    wifi.requestNetworkName()
    precondition(auth.requests == 1 && wifi.nameAccess == .notRequested)
    auth.change(to: .denied)
    precondition(wifi.nameAccess == .denied && wifi.networkName == nil && wifi.message != nil)
    wifi.requestNetworkName()
    precondition(auth.requests == 1, "A denied permission cannot be re-prompted by the app")
    let deniedReads = await hardware.reads
    precondition(!deniedReads.contains(true))
    wifi.stop()
    auth.change(to: .authorized)
    wifi.start()
    try await wait({ wifi.networkName == "Example network" }, "Granted permission should allow SSID")
    precondition(wifi.nameAccess == .authorized && wifi.message == nil,
                 "Authorization granted while closed must clear the previous permission error on reopen")
    auth.change(to: .restricted)
    precondition(wifi.networkName == nil && wifi.nameAccess == .restricted)
    wifi.clearMessage()

    wifi.setPower(false)
    precondition(wifi.isBusy && wifi.isPowerOn == true, "A toggle is not optimistic")
    wifi.setPower(false)
    try await wait({ await hardware.hasPendingWrite }, "Expected simulated write")
    await hardware.finishWrite(actual: true, accepted: false)
    try await wait({ !wifi.isBusy }, "A failed write did not finish")
    precondition(wifi.isPowerOn == true && wifi.message == "未能更改 Wi-Fi 状态，请打开系统设置")
    let writes = await hardware.writes
    precondition(writes == [false], "Only one operation may be in flight")
    wifi.setPower(false)
    try await wait({ await hardware.hasPendingWrite }, "Expected second simulated write")
    await hardware.finishWrite(actual: true, accepted: true)
    try await wait({ !wifi.isBusy }, "Unverified write did not finish")
    precondition(wifi.isPowerOn == true && wifi.message != nil, "Do not report success without read-back")

    wifi.setPower(false)
    try await wait({ await hardware.hasPendingWrite }, "Expected third simulated write")
    await hardware.finishWrite(actual: false, accepted: false)
    try await wait({ !wifi.isBusy }, "Concurrent state change did not finish")
    precondition(wifi.isPowerOn == false && wifi.message == nil,
                 "The requested state has been reached even if this setter returned an error")

    wifi.setPower(true)
    try await wait({ await hardware.hasPendingWrite }, "Expected fourth simulated write")
    wifi.stop()
    precondition(wifi.isBusy)
    await hardware.finishWrite(actual: true, accepted: true)
    try await wait({ !wifi.isBusy }, "Closing should not cancel a submitted operation")
    precondition(wifi.isPowerOn == false, "Closed panel must ignore late hardware publications")
    wifi.start()
    try await wait({ wifi.isPowerOn == true }, "Reopening should read the actual result")

    await hardware.delayNextRead()
    wifi.refresh()
    try await wait({ await hardware.hasPendingRead }, "Expected delayed status read")
    let center = NSWorkspace.shared.notificationCenter
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    wifi.setPower(false)
    wifi.refresh()
    let beforeSleepReads = await hardware.reads.count
    await hardware.finishStaleRead()
    try await Task.sleep(for: .milliseconds(10))
    let afterSleepReads = await hardware.reads.count
    precondition(afterSleepReads == beforeSleepReads && !wifi.isBusy && wifi.isPowerOn == true && wifi.networkName == nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await wait({ await hardware.reads.count == afterSleepReads + 1 }, "Wake must refresh an open panel once")
    print("PASS: Wi-Fi power read-back, failed/unsupported changes, explicit SSID consent, close during actions and sleep/wake")
}
