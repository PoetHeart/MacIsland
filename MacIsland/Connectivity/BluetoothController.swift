import AppKit
import Combine
import CoreBluetooth
import IOBluetooth

enum BluetoothAccess: Equatable { case notRequested, allowed, denied, restricted, unavailable }

enum BluetoothDeviceKind: Equatable {
    case headphones, speaker, mouse, keyboard, trackpad, controller, computer, other

    var symbol: String {
        switch self {
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .controller: return "gamecontroller"
        case .computer: return "desktopcomputer"
        case .other: return "wave.3.right"
        }
    }

    var isInputDevice: Bool {
        switch self {
        case .mouse, .keyboard, .trackpad, .controller, .other: return true // Unknown devices might be input devices.
        default: return false
        }
    }

    static func classify(name: String, major: Int, minor: Int) -> Self {
        if name.localizedCaseInsensitiveContains("trackpad") || name.contains("触控板") { return .trackpad }
        if major == kBluetoothDeviceClassMajorPeripheral {
            switch minor & 0x30 {
            case kBluetoothDeviceClassMinorPeripheral1Keyboard, kBluetoothDeviceClassMinorPeripheral1Combo: return .keyboard
            case kBluetoothDeviceClassMinorPeripheral1Pointing: return .mouse
            default:
                if [1, 2].contains(minor & 0x0f) { return .controller }
            }
        }
        if major == kBluetoothDeviceClassMajorAudio {
            switch minor {
            case kBluetoothDeviceClassMinorAudioHeadset, kBluetoothDeviceClassMinorAudioHandsFree,
                 kBluetoothDeviceClassMinorAudioHeadphones: return .headphones
            case kBluetoothDeviceClassMinorAudioLoudspeaker, kBluetoothDeviceClassMinorAudioHiFi,
                 kBluetoothDeviceClassMinorAudioPortable: return .speaker
            default: break
            }
        }
        if major == kBluetoothDeviceClassMajorComputer { return .computer }
        return .other
    }
}

struct BluetoothDeviceItem: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: BluetoothDeviceKind
    let isConnected: Bool
    let canControl: Bool
}

@MainActor protocol BluetoothRadioReading: AnyObject {
    var authorization: BluetoothAccess { get }
    var isPoweredOn: Bool? { get }
    func observe(request: Bool, onChange: @escaping () -> Void)
    func stop()
}

@MainActor
private final class SystemBluetoothRadio: NSObject, BluetoothRadioReading, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var onChange: (() -> Void)?

    var authorization: BluetoothAccess {
        if central?.state == .unsupported { return .unavailable }
        switch CBCentralManager.authorization {
        case .notDetermined: return .notRequested
        case .restricted: return .restricted
        case .denied: return .denied
        case .allowedAlways:
            if central?.state == .unauthorized { return .denied }
            return .allowed
        @unknown default: return .unavailable
        }
    }

    var isPoweredOn: Bool? {
        switch central?.state {
        case .poweredOn: return true
        case .poweredOff: return false
        default: return nil
        }
    }

    func observe(request: Bool, onChange: @escaping () -> Void) {
        self.onChange = onChange
        // Reading the static authorization is passive. Creating a manager may show TCC's prompt.
        guard central == nil, authorization == .allowed || (request && authorization == .notRequested) else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self, self.central === central else { return }
            onChange?()
        }
    }

    func stop() {
        central?.delegate = nil
        central = nil
        onChange = nil
    }
}

enum BluetoothWriteResult { case accepted, missing, unsupported, failed }

/// Synchronous methods run only on the controller's serial worker, never on the main thread.
protocol PairedBluetoothReading: AnyObject, Sendable {
    func paired() -> [BluetoothDeviceItem]
    func write(connected: Bool, id: String) -> BluetoothWriteResult
}

private final class SystemPairedBluetooth: PairedBluetoothReading {
    private func pairedHandles() -> [IOBluetoothDevice] {
        guard CBCentralManager.authorization == .allowedAlways else { return [] }
        return IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }

    private func item(for device: IOBluetoothDevice) -> BluetoothDeviceItem? {
        guard let address = device.addressString, !address.isEmpty else { return nil }
        let id = address.uppercased()
        let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (name?.isEmpty == false ? name : nil) ?? id
        let kind = BluetoothDeviceKind.classify(name: title, major: Int(device.deviceClassMajor),
                                                minor: Int(device.deviceClassMinor))
        // A cached classic SDP record is evidence of BR/EDR support. Do not probe by connecting:
        // paired LE peripherals without a classic profile must be managed in System Settings.
        let canControl = !(device.services?.isEmpty ?? true)
        return BluetoothDeviceItem(id: id, name: title, kind: kind, isConnected: device.isConnected(),
                                   canControl: canControl)
    }

    func paired() -> [BluetoothDeviceItem] {
        var seen = Set<String>()
        return pairedHandles().compactMap(item(for:)).filter { seen.insert($0.id).inserted }.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func write(connected: Bool, id: String) -> BluetoothWriteResult {
        // Resolve the device again. A stale row must never target a newly paired device with the same name.
        guard let device = pairedHandles().first(where: { $0.addressString?.uppercased() == id }),
              let item = item(for: device) else { return .missing }
        guard item.canControl else { return .unsupported }
        if device.isConnected() == connected { return .accepted }
        // 0x2000 Bluetooth page-timeout slots × 0.625 ms ≈ 5.12 seconds.
        let status = connected ? device.openConnection(nil, withPageTimeout: 0x2000, authenticationRequired: true)
                               : device.closeConnection()
        return status == kIOReturnSuccess ? .accepted : .failed
    }
}

private struct BluetoothOperationResult {
    let devices: [BluetoothDeviceItem]
    let message: String
}

@MainActor
final class BluetoothController: ObservableObject {
    @Published private(set) var devices: [BluetoothDeviceItem] = []
    @Published private(set) var authorization: BluetoothAccess = .notRequested
    @Published private(set) var isPoweredOn: Bool?
    @Published private(set) var isLoading = false
    @Published private(set) var busyDeviceID: String?
    @Published private(set) var message: String?

    private let radio: BluetoothRadioReading
    private let reader: PairedBluetoothReading
    private let queue = DispatchQueue(label: "MacIsland.bluetooth.paired", qos: .userInitiated)
    private let verifyDelay: TimeInterval
    private var active = false
    private var suspended = false
    private var generation: UInt = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    convenience init() { self.init(radio: SystemBluetoothRadio(), reader: SystemPairedBluetooth()) }
    init(radio: BluetoothRadioReading, reader: PairedBluetoothReading, verifyDelay: TimeInterval = 0.2) {
        self.radio = radio
        self.reader = reader
        self.verifyDelay = verifyDelay
        self.authorization = radio.authorization
    }

    deinit {
        timer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }

    func start() {
        guard !active else { return }
        active = true
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSuspended(true) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSuspended(false) }
            }
        ]
        watchRadio(request: false)
    }

    func stop() {
        guard active else { return }
        active = false
        suspended = false
        invalidateReads()
        timer?.invalidate()
        timer = nil
        radio.stop()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        // Discard feedback already shown. An operation still running will post its result later.
        if busyDeviceID == nil { clearMessage() }
    }

    func requestAccess() {
        if !active { start() }
        guard !suspended else { return }
        watchRadio(request: true)
    }

    func refresh() {
        guard active, !suspended else { return }
        watchRadio(request: false)
    }

    func clearMessage() { message = nil }

    func setConnected(_ connected: Bool, for id: String) {
        guard busyDeviceID == nil, active, !suspended else { return }
        guard radio.authorization == .allowed, radio.isPoweredOn == true else {
            message = "蓝牙不可用"
            return
        }
        guard let row = devices.first(where: { $0.id == id }) else { message = "设备已不在配对列表中"; return }
        guard row.canControl else { message = "请在系统蓝牙设置中管理此设备"; return }
        invalidateReads()
        message = nil
        busyDeviceID = id
        let backend = reader
        let delay = verifyDelay
        queue.async { [weak self] in
            let result = Self.apply(connected, id: id, backend: backend, delay: delay)
            Task { @MainActor in
                guard let self else { return }
                self.busyDeviceID = nil
                if self.radio.authorization == .allowed && self.radio.isPoweredOn != false {
                    self.devices = result.devices
                    self.message = result.message
                    // The user can reopen before the new manager has reported its first power state.
                    // Keep the verified result while waiting for the delegate's powered-on/off update.
                    if self.active && self.radio.isPoweredOn == nil { self.refresh() }
                } else {
                    self.devices = []
                    self.message = "蓝牙不可用"
                }
            }
        }
    }

    private nonisolated static func apply(_ connected: Bool, id: String, backend: PairedBluetoothReading,
                                         delay: TimeInterval) -> BluetoothOperationResult {
        var rows = backend.paired()
        func result(_ text: String) -> BluetoothOperationResult { .init(devices: rows, message: text) }
        guard let target = rows.first(where: { $0.id == id }) else { return result("设备已不在配对列表中") }
        guard target.canControl else { return result("请在系统蓝牙设置中管理此设备") }
        let completed = connected ? "设备已连接" : "设备已断开"
        if target.isConnected == connected { return result(completed) }
        let status = backend.write(connected: connected, id: id)
        rows = backend.paired()
        // macOS can return “connection exists” if another client established the link first.
        // Report verified state for this paired address, regardless of which client changed it.
        if let observed = rows.first(where: { $0.id == id }), observed.isConnected == connected {
            return result(completed)
        }
        switch status {
        case .missing: return result("设备已不在配对列表中")
        case .unsupported: return result("请在系统蓝牙设置中管理此设备")
        case .failed: return result(connected ? "蓝牙连接失败" : "蓝牙断开失败")
        case .accepted: break
        }
        // A successful API return is not proof that the device reached the requested state.
        for attempt in 0..<6 {
            guard let device = rows.first(where: { $0.id == id }) else { return result("设备已不在配对列表中") }
            if device.isConnected == connected { return result(completed) }
            if attempt < 5 {
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                rows = backend.paired()
            }
        }
        return result("未能确认设备连接状态")
    }

    private func watchRadio(request: Bool) {
        radio.observe(request: request) { [weak self] in self?.radioDidChange() }
        radioDidChange()
    }

    private func radioDidChange() {
        guard active, !suspended else { return }
        authorization = radio.authorization
        isPoweredOn = radio.isPoweredOn
        guard authorization == .allowed, isPoweredOn == true else {
            invalidateReads()
            if authorization != .allowed || isPoweredOn == false { devices = [] }
            timer?.invalidate()
            timer = nil
            return
        }
        if timer == nil {
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        guard busyDeviceID == nil, !isLoading else { return }
        let token = generation
        let backend = reader
        isLoading = true
        queue.async { [weak self] in
            let rows = backend.paired()
            Task { @MainActor in
                guard let self, self.generation == token, self.active, !self.suspended else { return }
                self.isLoading = false
                guard self.radio.authorization == .allowed, self.radio.isPoweredOn == true else {
                    self.radioDidChange()
                    return
                }
                self.devices = rows
            }
        }
    }

    private func invalidateReads() { generation &+= 1; isLoading = false }

    private func setSuspended(_ newValue: Bool) {
        guard active, suspended != newValue else { return }
        suspended = newValue
        if newValue {
            invalidateReads()
            timer?.invalidate()
            timer = nil
            radio.stop()
        } else {
            watchRadio(request: false)
        }
    }
}
