import AppKit
import SwiftUI

enum ConnectivitySettingsDestination {
    case wifi, bluetooth, locationPrivacy, bluetoothPrivacy
}

@MainActor
struct ConnectivityPanelView: View {
    @ObservedObject var settings: IslandSettings
    @ObservedObject var status: SystemStatusMonitor
    @ObservedObject var wifi: WiFiController
    @ObservedObject var bluetooth: BluetoothController
    let openSettings: () -> Void
    let openSystemSettings: (ConnectivitySettingsDestination) -> Void

    private enum Page { case home, wifi, bluetooth }

    @State private var page: Page = .home
    @State private var confirmingID: String?
    @State private var pendingAction: (id: String, connect: Bool)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(settings: IslandSettings, status: SystemStatusMonitor, wifi: WiFiController,
         bluetooth: BluetoothController, openSettings: @escaping () -> Void,
         openSystemSettings: @escaping (ConnectivitySettingsDestination) -> Void) {
        self.settings = settings
        self.status = status
        self.wifi = wifi
        self.bluetooth = bluetooth
        self.openSettings = openSettings
        self.openSystemSettings = openSystemSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            // Keep the header and footer reachable even when there are many paired devices.
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView { content }
                    .scrollIndicators(.automatic)
            }
            HStack {
                Button(action: openSettings) {
                    Label(t("MacIsland 设置"), systemImage: "gearshape")
                }
                .buttonStyle(.link)
                Spacer()
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .onChange(of: status.snapshot.wifi) { _, _ in wifi.refresh() }
        .onChange(of: wifi.isPowerOn) { _, _ in status.refresh() }
        .onChange(of: confirmableIDs) { _, ids in
            if let confirmingID, !ids.contains(confirmingID) { self.confirmingID = nil }
        }
        .onChange(of: bluetooth.busyDeviceID) { _, id in
            if id == nil { pendingAction = nil }
            else { confirmingID = nil }
        }
    }

    private func t(_ key: String) -> String {
        ConnectivityText.text(key, language: settings.language)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if page != .home {
                Button { navigate(.home) } label: {
                    Image(systemName: "chevron.backward").frame(width: 22, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("返回"))
                .help(t("返回"))
                .keyboardShortcut("[", modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(page == .home ? "MacIsland" : page == .wifi ? "Wi-Fi" : t("蓝牙"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(page == .home ? t("连接与状态") : page == .wifi ? t("无线网络") : bluetoothSummary)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if page != .home {
                Button {
                    if page == .wifi { wifi.refresh(); status.refresh() }
                    else { bluetooth.refresh() }
                } label: { Image(systemName: "arrow.clockwise").frame(width: 22, height: 24) }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("刷新"))
                .help(t("刷新"))
                .keyboardShortcut("r", modifiers: .command)
                .disabled(page == .wifi ? wifi.isBusy : bluetooth.authorization != .allowed
                          || bluetooth.isLoading || bluetooth.busyDeviceID != nil)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch page {
            case .home: home
            case .wifi: wifiDetail
            case .bluetooth: bluetoothDetail
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(page)
        .transition(.opacity)
    }

    private func navigate(_ target: Page) {
        withAnimation(reduceMotion || !settings.animationsEnabled ? nil : .spring(duration: 0.20, bounce: 0.06)) {
            confirmingID = nil
            page = target
        }
        // Only explicit navigation may prompt. Opening the menu-bar panel never does.
        if target == .bluetooth {
            if bluetooth.authorization == .notRequested { bluetooth.requestAccess() }
            else if bluetooth.authorization == .allowed { bluetooth.refresh() }
        } else if target == .wifi { wifi.refresh() }
    }

    @ViewBuilder private var home: some View {
        card {
            navRow("Wi-Fi", wifiSummary, wifiSymbol, wifi.isPowerOn == true) { navigate(.wifi) }
            rule
            navRow(t("蓝牙"), bluetoothSummary, "antenna.radiowaves.left.and.right",
                   bluetooth.authorization == .allowed && bluetooth.isPoweredOn == true) { navigate(.bluetooth) }
        }
        if bluetooth.authorization == .allowed, bluetooth.isPoweredOn == true, !bluetooth.devices.isEmpty {
            let preview = Array((connected + disconnected).prefix(2))
            deviceSection(t("我的设备"), devices: preview)
            linkRow(t("全部蓝牙设备"), symbol: "chevron.forward") { navigate(.bluetooth) }
        }
        if let message = bluetooth.message { feedback(message) }
        sectionTitle(t("系统状态"))
        card {
            statusRow(t("电量"), value: batteryValue, symbol: status.snapshot.battery.isCharging ? "bolt.batteryblock" : "battery.100percent")
            rule
            statusRow(t("音量"), value: audioValue, symbol: status.snapshot.audio.isMuted ? "speaker.slash" : "speaker.wave.2")
        }
    }

    private var wifiSymbol: String { wifi.isPowerOn == false ? "wifi.slash" : "wifi" }
    private var wifiSummary: String {
        if wifi.isPowerOn == false { return t("已关闭") }
        switch status.snapshot.wifi {
        case .unavailable: return t("暂不可用")
        case .off: return wifi.isPowerOn == true ? t("正在更新…") : t("已关闭")
        case .disconnected: return t("未连接")
        case let .connected(strength):
            let signal: String
            switch strength {
            case 3?: signal = "信号强"
            case 2?: signal = "信号中等"
            case 0?, 1?: signal = "信号弱"
            default: signal = "信号未知"
            }
            return t("已连接") + " · " + t(signal)
        }
    }

    @ViewBuilder private var wifiDetail: some View {
        card {
            HStack(spacing: 12) {
                badge(wifiSymbol, active: wifi.isPowerOn == true)
                copy("Wi-Fi", wifi.isBusy ? t("正在更新…") : powerText(wifi.isPowerOn))
                Spacer()
                if wifi.isBusy { spinner }
                Toggle("Wi-Fi", isOn: Binding(get: { wifi.isPowerOn == true }, set: { target in
                    if !wifi.isBusy, wifi.isPowerOn != nil { wifi.setPower(target) }
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(wifi.isPowerOn == nil || wifi.isBusy)
            }
            .padding(12)
        }
        if wifi.isPowerOn != false {
            sectionTitle(t("当前网络"))
            card {
                HStack(spacing: 12) {
                    badge("wifi", active: wifiConnected)
                    if wifiConnected, wifi.nameAccess == .authorized, let name = wifi.networkName, !name.isEmpty {
                        copy(name, wifiSummary)
                    } else { Text(wifiSummary).font(.headline) }
                    Spacer()
                }
                .padding(12)
                if wifiConnected {
                    switch wifi.nameAccess {
                    case .notRequested:
                        rule
                        linkRow(t("显示网络名称"), symbol: "location") {
                            NSApp.activate()
                            wifi.requestNetworkName()
                        }
                    case .denied, .restricted:
                        rule
                        linkRow(t("定位权限设置…"), symbol: "arrow.up.right") { openSystemSettings(.locationPrivacy) }
                    case .authorized, .unavailable: EmptyView()
                    }
                }
            }
            if wifiConnected {
                switch wifi.nameAccess {
                case .notRequested: note("显示网络名称需要定位权限，这是可选的。")
                case .denied, .restricted: note("未允许读取网络名称。")
                case .unavailable: note("定位服务当前不可用。")
                case .authorized:
                    if wifi.networkName?.isEmpty != false { note("当前无法读取网络名称。") }
                }
            }
        }
        if let message = wifi.message { feedback(message) }
        card { linkRow(t("Wi-Fi 设置…"), symbol: "arrow.up.right") { openSystemSettings(.wifi) } }
        note("在系统设置中选择网络或输入密码。")
    }

    private var wifiConnected: Bool {
        if case .connected = status.snapshot.wifi { return wifi.isPowerOn != false }
        return false
    }

    private var connected: [BluetoothDeviceItem] { bluetooth.devices.filter(\.isConnected) }
    private var disconnected: [BluetoothDeviceItem] { bluetooth.devices.filter { !$0.isConnected } }

    private var bluetoothSummary: String {
        switch bluetooth.authorization {
        case .notRequested: return t("查看已配对设备")
        case .denied: return t("未允许蓝牙访问。")
        case .restricted: return t("蓝牙访问受到系统限制。")
        case .unavailable: return t("暂不可用")
        case .allowed:
            if bluetooth.isPoweredOn != true { return powerText(bluetooth.isPoweredOn) }
            if bluetooth.isLoading && bluetooth.devices.isEmpty { return t("正在读取…") }
            return ConnectivityText.connectedCount(connected.count, language: settings.language)
        }
    }

    @ViewBuilder private var bluetoothDetail: some View {
        card {
            statusRow(t("蓝牙状态"), value: powerText(bluetooth.isPoweredOn),
                      symbol: "antenna.radiowaves.left.and.right")
        }
        if let message = bluetooth.message { feedback(message) }
        switch bluetooth.authorization {
        case .notRequested:
            note("允许访问蓝牙后，可查看兼容的已配对设备。")
            if bluetooth.isLoading { spinner }
            else { card { linkRow(t("允许蓝牙访问"), symbol: "lock.open") { bluetooth.requestAccess() } } }
        case .denied, .restricted:
            note(bluetooth.authorization == .denied ? "未允许蓝牙访问。" : "蓝牙访问受到系统限制。")
            card { linkRow(t("蓝牙权限设置…"), symbol: "arrow.up.right") { openSystemSettings(.bluetoothPrivacy) } }
        case .unavailable: note("蓝牙当前不可用。")
        case .allowed:
            if bluetooth.isPoweredOn == false { note("请在系统设置中打开蓝牙。") }
            else if bluetooth.isLoading && bluetooth.devices.isEmpty {
                HStack { spinner; note("正在读取…") }
            } else if bluetooth.isPoweredOn == nil { note("蓝牙当前不可用。") }
            else if bluetooth.devices.isEmpty { note("没有可显示的已配对设备。") }
            else {
                if !connected.isEmpty { deviceSection(t("已连接"), devices: connected) }
                if !disconnected.isEmpty { deviceSection(t("我的设备"), devices: disconnected) }
            }
        }
        card { linkRow(t("蓝牙设置…"), symbol: "arrow.up.right") { openSystemSettings(.bluetooth) } }
        note("在系统设置中配对新设备或开关蓝牙。")
    }

    private func deviceSection(_ title: String, devices: [BluetoothDeviceItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            card {
                ForEach(devices, id: \.id) { device in
                    if device.id != devices.first?.id { rule }
                    deviceRow(device)
                }
            }
        }
    }

    private var confirmableIDs: [String] {
        guard bluetooth.authorization == .allowed, bluetooth.isPoweredOn == true,
              bluetooth.busyDeviceID == nil else { return [] }
        let devices = page == .home ? Array((connected + disconnected).prefix(2)) : bluetooth.devices
        return devices.filter { $0.kind.isInputDevice && $0.isConnected && $0.canControl }.map(\.id)
    }

    private func deviceRow(_ device: BluetoothDeviceItem) -> some View {
        let busy = bluetooth.busyDeviceID == device.id
        let confirmed = confirmingID == device.id && confirmableIDs.contains(device.id)
        let action = busy ? busyText(for: device.id) : t(device.isConnected ? "断开" : "连接")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                badge(device.kind.symbol, active: device.isConnected)
                copy(device.name, t(kindKey(device.kind)) + " · " + t(device.isConnected ? "已连接" : "未连接"))
                Spacer(minLength: 0)
                if busy { spinner }
                if device.canControl {
                    Button(action) {
                        guard bluetooth.busyDeviceID == nil else { return }
                        if device.isConnected && device.kind.isInputDevice { confirmingID = device.id }
                        else { submit(!device.isConnected, id: device.id) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(bluetooth.busyDeviceID != nil || confirmed)
                    .accessibilityLabel(action + " · " + device.name)
                } else {
                    Button { openSystemSettings(.bluetooth) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(t("请在蓝牙设置中操作") + " · " + device.name)
                        .help(t("请在蓝牙设置中操作"))
                }
            }
            if confirmed {
                Text(t("断开后，此设备将暂时无法控制电脑。"))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(t("取消")) { confirmingID = nil }
                    Button(t("确认断开"), role: .destructive) {
                        guard confirmableIDs.contains(device.id) else { confirmingID = nil; return }
                        submit(false, id: device.id)
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 60)
    }

    private func submit(_ connect: Bool, id: String) {
        guard bluetooth.authorization == .allowed, bluetooth.isPoweredOn == true,
              bluetooth.busyDeviceID == nil, let current = bluetooth.devices.first(where: { $0.id == id }),
              current.canControl, current.isConnected != connect else { return }
        confirmingID = nil
        pendingAction = (id, connect)
        bluetooth.setConnected(connect, for: id)
    }

    private func busyText(for id: String) -> String {
        if let pendingAction, pendingAction.id == id { return t(pendingAction.connect ? "连接中…" : "断开中…") }
        return t("处理中…")
    }

    private func kindKey(_ kind: BluetoothDeviceKind) -> String {
        switch kind {
        case .headphones: return "耳机"
        case .speaker: return "扬声器"
        case .mouse: return "鼠标"
        case .keyboard: return "键盘"
        case .trackpad: return "触控板"
        case .controller: return "游戏控制器"
        case .computer: return "电脑"
        case .other: return "蓝牙设备"
        }
    }

    private func powerText(_ power: Bool?) -> String {
        power.map { t($0 ? "已打开" : "已关闭") } ?? t("暂不可用")
    }

    private func percentage(_ value: Double?) -> String {
        guard let value = SystemStatusValues.level(value) else { return t("暂不可用") }
        return "\(Int((value * 100).rounded()))%"
    }
    private var batteryValue: String {
        let battery = status.snapshot.battery
        var value = battery.isPresent ? percentage(battery.level) : t("无内置电池")
        if battery.isCharging { value += " · " + t("正在充电") }
        else if battery.isPluggedIn { value += " · " + t("已接电源") }
        return value
    }
    private var audioValue: String {
        status.snapshot.audio.isMuted ? t("已静音") : percentage(status.snapshot.audio.level)
    }

    private var rule: some View { Divider().padding(.horizontal, 12).accessibilityHidden(true) }
    private var spinner: some View { ProgressView().controlSize(.small).accessibilityLabel(t("正在更新…")) }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.leading, 4).accessibilityAddTraits(.isHeader)
    }

    private func card<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0, content: rows)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.055))
            }
    }
    private func copy(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).lineLimit(2).truncationMode(.middle)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
    private func badge(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(width: 32, height: 32)
            .background((active ? Color.accentColor : Color.secondary).opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
    private func navRow(_ title: String, _ subtitle: String, _ symbol: String, _ active: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                badge(symbol, active: active)
                copy(title, subtitle)
                Spacer()
                Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }.padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(subtitle)
    }
    private func statusRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22).accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.callout).padding(12).accessibilityElement(children: .combine)
    }
    private func linkRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol).font(.callout).accessibilityHidden(true)
            }.padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
    }
    private func note(_ key: String) -> some View {
        Text(t(key)).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func feedback(_ message: String) -> some View {
        Text(t(message)).font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
