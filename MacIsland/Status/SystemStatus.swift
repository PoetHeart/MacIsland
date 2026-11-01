import AppKit
import Combine
import CoreAudio
import CoreWLAN
import IOKit.ps

struct BatteryStatus: Equatable {
    var level: Double?
    var isCharging: Bool
    var isPluggedIn: Bool
    var isPresent: Bool

    static let unknown = BatteryStatus(level: nil, isCharging: false, isPluggedIn: false, isPresent: true)
}

enum WiFiStatus: Equatable {
    case unavailable
    case off
    case disconnected
    case connected(strength: Int?)
}

struct AudioStatus: Equatable {
    var level: Double?
    var isMuted: Bool
}

struct SystemStatusSnapshot: Equatable {
    var battery: BatteryStatus
    var wifi: WiFiStatus
    var audio: AudioStatus

    static let unknown = SystemStatusSnapshot(battery: .unknown, wifi: .unavailable,
                                              audio: AudioStatus(level: nil, isMuted: false))
}

/// Hardware readings can be absent, stale or malformed. Missing data never becomes 0%.
enum SystemStatusValues {
    static func level(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    static func batteryLevel(current: Double?, maximum: Double?) -> Double? {
        guard let current, let maximum, current.isFinite, maximum.isFinite,
              current >= 0, maximum > 0 else { return nil }
        return level(current / maximum)
    }

    static func signalStrength(rssi: Int) -> Int? {
        // CoreWLAN returns 0 when RSSI is unavailable; do not draw a full-strength icon.
        guard (-127 ... -1).contains(rssi) else { return nil }
        if rssi >= -55 { return 3 }
        if rssi >= -70 { return 2 }
        if rssi >= -85 { return 1 }
        return 0
    }

    static func wifi(powerOn: Bool, mode: CWInterfaceMode, rssi: Int) -> WiFiStatus {
        guard powerOn else { return .off }
        switch mode {
        case .station, .IBSS: return .connected(strength: signalStrength(rssi: rssi))
        case .hostAP: return .connected(strength: nil)
        case .none: return .disconnected
        @unknown default: return .unavailable
        }
    }

    static func audioLevel(master: Double?, channels: [Double?]) -> Double? {
        if let master = level(master) { return master }
        let valid = channels.compactMap { level($0) }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    static func muted(master: Bool?, channels: [Bool?]) -> Bool {
        if let master { return master }
        return !channels.isEmpty && channels.allSatisfy { $0 == true }
    }
}

/// Injectable boundary keeps lifecycle checks independent of a Mac's current hardware.
protocol SystemStatusReading: AnyObject {
    func start(deliver: @escaping (SystemStatusSnapshot) -> Void)
    func stop()
    func refresh()
}

@MainActor
final class SystemStatusMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemStatusSnapshot.unknown

    private let reader: SystemStatusReading
    private var requested = false
    private var active = false
    private var generation: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?

    init(reader: SystemStatusReading = HardwareStatusReader()) {
        self.reader = reader
    }

    func start() {
        guard !requested else { return }
        requested = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.requested else { return }
                self.activate()
            }
        })
        activate()
    }

    func stop() {
        requested = false
        suspend()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    func refresh() {
        guard active else { return }
        reader.refresh()
    }

    private func activate() {
        guard requested, !active else { return }
        active = true
        generation &+= 1
        let currentGeneration = generation
        reader.start { [weak self] value in
            Task { @MainActor in
                guard let self, self.active, self.generation == currentGeneration else { return }
                if self.snapshot != value { self.snapshot = value }
            }
        }
        // This source only schedules background work; it never reads hardware on the main thread.
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemStatusMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak monitor] in monitor?.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }

    private func suspend() {
        guard active else { return }
        active = false
        generation &+= 1
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
        reader.stop()
    }

    deinit {
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        reader.stop()
    }
}

/// All hardware calls and mutable state below are confined to `queue`.
final class HardwareStatusReader: SystemStatusReading, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacIsland.system-status", qos: .utility)
    private var active = false
    private var deliver: ((SystemStatusSnapshot) -> Void)?
    private var timer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var wifiClient: CWWiFiClient?
    private var wifiDelegate: WiFiEventDelegate?
    private var wifiEvents: [CWEventType] = []
    private var audioListeners: [AudioListener] = []
    private var outputDevice: AudioObjectID = kAudioObjectUnknown
    private var outputChannels: UInt32 = 0

    func start(deliver: @escaping (SystemStatusSnapshot) -> Void) {
        queue.async { [self] in
            guard !active else { return }
            active = true
            self.deliver = deliver
            setupWiFi()
            addAudioListener(object: AudioObjectID(kAudioObjectSystemObject),
                             selector: kAudioHardwarePropertyDefaultOutputDevice,
                             scope: kAudioObjectPropertyScopeGlobal)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(3))
            timer.setEventHandler { [weak self] in self?.read() }
            self.timer = timer
            timer.resume()
            read()
        }
    }

    func stop() {
        queue.async { [self] in
            active = false
            deliver = nil
            pending?.cancel()
            pending = nil
            timer?.cancel()
            timer = nil
            removeAudioListeners()
            outputDevice = kAudioObjectUnknown
            outputChannels = 0
            tearDownWiFi()
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.scheduleRead() }
    }

    private func scheduleRead() {
        guard active, pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.read()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func read() {
        guard active else { return }
        if wifiClient == nil { setupWiFi() }
        let value = SystemStatusSnapshot(battery: readBattery(), wifi: readWiFi(), audio: readAudio())
        deliver?(value)
    }

    private func readBattery() -> BatteryStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unknown
        }
        var unreadableSource = false
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String else {
                unreadableSource = true
                continue
            }
            guard type == kIOPSInternalBatteryType else { continue }
            let present = (description[kIOPSIsPresentKey] as? NSNumber)?.boolValue ?? true
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            return BatteryStatus(level: present ? SystemStatusValues.batteryLevel(current: current, maximum: maximum) : nil,
                                 isCharging: present && ((description[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false),
                                 isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                 isPresent: present)
        }
        guard !unreadableSource else { return .unknown }
        let provider = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return BatteryStatus(level: nil, isCharging: false,
                             isPluggedIn: provider == kIOPMACPowerKey, isPresent: false)
    }

    private func setupWiFi() {
        let client = CWWiFiClient()
        let delegate = WiFiEventDelegate { [weak self] invalidated in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.active else { return }
                if invalidated { self.tearDownWiFi() }
                self.scheduleRead()
            }
        }
        client.delegate = delegate
        wifiClient = client
        wifiDelegate = delegate
        for event: CWEventType in [.powerDidChange, .linkDidChange, .linkQualityDidChange, .modeDidChange] {
            do {
                try client.startMonitoringEvent(with: event)
                wifiEvents.append(event)
            } catch {
                // Some OS/interface combinations decline events; slow polling remains available.
            }
        }
    }

    private func tearDownWiFi() {
        wifiClient?.delegate = nil
        for event in wifiEvents { try? wifiClient?.stopMonitoringEvent(with: event) }
        wifiEvents.removeAll()
        wifiDelegate = nil
        wifiClient = nil
    }

    private func readWiFi() -> WiFiStatus {
        guard let interface = wifiClient?.interface() else { return .unavailable }
        // SSID, BSSID, country code and scans are intentionally never requested.
        return SystemStatusValues.wifi(powerOn: interface.powerOn(), mode: interface.interfaceMode(),
                                       rssi: interface.rssiValue())
    }

    private func readAudio() -> AudioStatus {
        let device: UInt32? = audioValue(object: AudioObjectID(kAudioObjectSystemObject),
                                        selector: kAudioHardwarePropertyDefaultOutputDevice,
                                        scope: kAudioObjectPropertyScopeGlobal)
        let current = device ?? kAudioObjectUnknown
        let channels = current == kAudioObjectUnknown ? 0 : channelCount(device: current)
        if current != outputDevice || channels != outputChannels {
            removeAudioListeners(keepingSystem: true)
            outputDevice = current
            outputChannels = channels
            if current != kAudioObjectUnknown {
                addAudioListener(object: current, selector: kAudioDevicePropertyStreamConfiguration)
                for element in 0 ... min(channels, 64) {
                    addAudioListener(object: current, selector: kAudioDevicePropertyVolumeScalar, element: element)
                    addAudioListener(object: current, selector: kAudioDevicePropertyMute, element: element)
                }
            }
        }
        guard current != kAudioObjectUnknown else { return AudioStatus(level: nil, isMuted: false) }
        func volume(_ element: UInt32) -> Double? {
            let value: Float32? = audioValue(object: current, selector: kAudioDevicePropertyVolumeScalar,
                                             element: element)
            return value.map(Double.init)
        }
        func mute(_ element: UInt32) -> Bool? {
            let value: UInt32? = audioValue(object: current, selector: kAudioDevicePropertyMute, element: element)
            return value.map { $0 != 0 }
        }
        let channelIDs: [UInt32] = channels > 0 ? Array(1 ... min(channels, 64)) : []
        return AudioStatus(level: SystemStatusValues.audioLevel(master: volume(0), channels: channelIDs.map(volume)),
                           isMuted: SystemStatusValues.muted(master: mute(0), channels: channelIDs.map(mute)))
    }

    private func channelCount(device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                mScope: kAudioObjectPropertyScopeOutput,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size <= 65_536 else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, data) == noErr else { return 0 }
        let buffers = data.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(buffers).reduce(0) { min(64, $0 + min(64, $1.mNumberChannels)) }
    }

    private func audioValue<T>(object: AudioObjectID, selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, data) == noErr,
              size == MemoryLayout<T>.size else { return nil }
        return data.load(as: T.self)
    }

    private struct AudioListener {
        var object: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }

    private func addAudioListener(object: AudioObjectID, selector: AudioObjectPropertySelector,
                                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRead() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return }
        audioListeners.append(AudioListener(object: object, address: address, block: block))
    }

    private func removeAudioListeners(keepingSystem: Bool = false) {
        audioListeners.removeAll { listener in
            if keepingSystem && listener.object == AudioObjectID(kAudioObjectSystemObject) { return false }
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.object, &address, queue, listener.block)
            return true
        }
    }
}

private final class WiFiEventDelegate: NSObject, CWEventDelegate {
    private let changed: (Bool) -> Void
    init(changed: @escaping (Bool) -> Void) { self.changed = changed }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { changed(false) }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { changed(false) }
    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) { changed(false) }
    func modeDidChangeForWiFiInterface(withName interfaceName: String) { changed(false) }
    func clientConnectionInterrupted() { changed(false) }
    func clientConnectionInvalidated() { changed(true) }
}
