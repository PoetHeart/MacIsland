import AppKit
import Combine
import CoreLocation
import CoreWLAN

enum WiFiNameAccess: Equatable {
    case notRequested, authorized, denied, restricted, unavailable
}

struct WiFiPanelReading: Equatable {
    let power: Bool?
    let name: String?
}

struct WiFiPowerResult: Equatable {
    let actual: Bool?
    let accepted: Bool
}

protocol WiFiPanelOperating: Sendable {
    func read(includeName: Bool) async -> WiFiPanelReading
    func setPower(_ enabled: Bool) async -> WiFiPowerResult
}

/// CoreWLAN calls can block. The client is created lazily and accessed only on this queue.
private final class CoreWLANPanelOperations: WiFiPanelOperating, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacIsland.wifi-controls", qos: .userInitiated)
    private lazy var client = CWWiFiClient.shared()

    func read(includeName: Bool) async -> WiFiPanelReading {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let interface = client.interface()
                let power = interface?.powerOn()
                let name = includeName && power == true ? interface?.ssid() : nil
                continuation.resume(returning: WiFiPanelReading(power: power, name: name))
            }
        }
    }

    func setPower(_ enabled: Bool) async -> WiFiPowerResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let interface = client.interface() else {
                    continuation.resume(returning: WiFiPowerResult(actual: nil, accepted: false))
                    return
                }
                let accepted: Bool
                do {
                    try interface.setPower(enabled)
                    accepted = true
                } catch {
                    accepted = false
                }
                continuation.resume(returning: WiFiPowerResult(actual: client.interface()?.powerOn(), accepted: accepted))
            }
        }
    }
}

@MainActor
protocol WiFiNameAuthorizing: AnyObject {
    var onChange: (() -> Void)? { get set }
    var access: WiFiNameAccess { get }
    func request()
}

/// Only initialized by the user's "Show network name" action. No coordinates are requested.
@MainActor
private final class CoreLocationNameAuthorization: NSObject, WiFiNameAuthorizing, CLLocationManagerDelegate {
    var onChange: (() -> Void)?
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()

    var access: WiFiNameAccess {
        switch manager.authorizationStatus {
        case .notDetermined: return .notRequested
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }

    func request() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.onChange?() }
    }
}

@MainActor
final class WiFiController: ObservableObject {
    @Published private(set) var isPowerOn: Bool?
    @Published private(set) var networkName: String?
    @Published private(set) var nameAccess: WiFiNameAccess = .notRequested
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    private let operations: WiFiPanelOperating
    private let authorization: WiFiNameAuthorizing
    private var showing = false
    private var sleeping = false
    private var nameEnabled = false
    private var sample: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var deferredMessage: String?
    private var observers: [NSObjectProtocol] = []

    convenience init() {
        self.init(operations: CoreWLANPanelOperations(), authorization: CoreLocationNameAuthorization())
    }

    init(operations: WiFiPanelOperating, authorization: WiFiNameAuthorizing) {
        self.operations = operations
        self.authorization = authorization
        authorization.onChange = { [weak self] in self?.authorizationChanged() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
    }

    func start() {
        guard !showing else { return }
        showing = true
        if !sleeping { beginSampling() }
    }

    func stop() {
        guard showing else { return }
        showing = false
        endSampling()
        // The user may have already submitted a real system operation. It completes independently.
    }

    func refresh() {
        guard showing, !sleeping, !isBusy else { return }
        updateAccess()
        guard sample == nil else { return }
        let includeName = nameEnabled && nameAccess == .authorized
        sample = Task { [weak self, operations] in
            guard !Task.isCancelled else { return }
            let reading = await operations.read(includeName: includeName)
            guard !Task.isCancelled, let self, self.showing, !self.sleeping else { return }
            self.sample = nil
            self.isPowerOn = reading.power
            self.updateAccess()
            self.networkName = includeName && self.nameAccess == .authorized && reading.power == true ? reading.name : nil
        }
    }

    func requestNetworkName() {
        guard showing, !sleeping else { return }
        nameEnabled = true
        updateAccess()
        switch nameAccess {
        case .notRequested:
            authorization.request()
        case .authorized:
            invalidateSample()
            refresh()
        case .denied, .restricted: message = "需要定位权限才能显示网络名称"
        case .unavailable: message = "定位服务不可用"
        }
    }

    func setPower(_ enabled: Bool) {
        guard showing, !sleeping, !isBusy else { return }
        guard isPowerOn != nil else { message = "未找到 Wi-Fi 接口"; return }
        invalidateSample()
        clearMessage()
        isBusy = true
        Task { [weak self, operations] in
            let result = await operations.setPower(enabled)
            guard let self else { return }
            // Another system client can reach the requested state even if this particular call failed.
            let failure: String? = result.actual == nil ? "未找到 Wi-Fi 接口" :
                result.actual == enabled ? nil : "未能更改 Wi-Fi 状态，请打开系统设置"
            self.isBusy = false
            guard self.showing, !self.sleeping else {
                self.deferredMessage = failure
                return
            }
            self.isPowerOn = result.actual
            if result.actual != true { self.networkName = nil }
            self.message = failure
            self.refresh()
        }
    }

    func clearMessage() { message = nil; deferredMessage = nil }

    private func updateAccess() {
        guard nameEnabled else { return }
        let actual = authorization.access
        if actual != nameAccess { nameAccess = actual }
        if actual != .authorized && networkName != nil { networkName = nil }
        if actual == .authorized && (message == "需要定位权限才能显示网络名称" || message == "定位服务不可用") {
            message = nil
        }
    }

    private func authorizationChanged() {
        guard nameEnabled, showing, !sleeping else { return }
        let previous = nameAccess
        updateAccess()
        guard nameAccess != previous else { return }
        invalidateSample()
        switch nameAccess {
        case .denied, .restricted: message = "需要定位权限才能显示网络名称"
        case .unavailable: message = "定位服务不可用"
        case .authorized, .notRequested: break
        }
        refresh()
    }

    private func beginSampling() {
        guard showing, !sleeping, polling == nil else { return }
        if let deferredMessage { message = deferredMessage; self.deferredMessage = nil }
        refresh()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self else { return }
                self.refresh()
            }
        }
    }

    private func invalidateSample() { sample?.cancel(); sample = nil }

    private func endSampling() {
        polling?.cancel()
        polling = nil
        invalidateSample()
        networkName = nil
    }

    private func willSleep() {
        guard !sleeping else { return }
        sleeping = true
        endSampling()
    }

    private func didWake() {
        guard sleeping else { return }
        sleeping = false
        if showing { beginSampling() }
    }

    deinit {
        polling?.cancel()
        sample?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
