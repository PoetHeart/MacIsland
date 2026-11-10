import Foundation

/// Keys are shared with the hardware controllers so feedback follows the selected app language.
enum ConnectivityText {
    static func text(_ key: String, language: String) -> String {
        if language == "en", let translation = english[key] { return translation }
        return AppText.text(key, language: language)
    }

    static func connectedCount(_ count: Int, language: String) -> String {
        if language == "en" { return "\(count) \(count == 1 ? "device" : "devices") connected" }
        return "\(count) 台设备已连接"
    }

    private static let english: [String: String] = [
        "连接与状态": "Connections & status",
        "无线网络": "Wireless network",
        "蓝牙": "Bluetooth",
        "返回": "Back",
        "刷新": "Refresh",
        "我的设备": "My devices",
        "全部蓝牙设备": "All Bluetooth devices",
        "系统状态": "System status",
        "当前网络": "Current network",
        "显示网络名称": "Show network name",
        "显示网络名称需要定位权限，这是可选的。": "Showing the network name requires location access. This is optional.",
        "当前无法读取网络名称。": "The network name is unavailable.",
        "定位服务当前不可用。": "Location services are unavailable.",
        "定位权限设置…": "Location Privacy Settings…",
        "未允许读取网络名称。": "Location access for the network name is not allowed.",
        "已打开": "On",
        "正在读取…": "Checking…",
        "正在更新…": "Updating…",
        "Wi-Fi 设置…": "Wi-Fi Settings…",
        "在系统设置中选择网络或输入密码。": "Choose a network or enter its password in System Settings.",
        "蓝牙设置…": "Bluetooth Settings…",
        "蓝牙状态": "Bluetooth status",
        "在系统设置中配对新设备或开关蓝牙。": "Pair new devices or turn Bluetooth on or off in System Settings.",
        "查看已配对设备": "View paired devices",
        "允许访问蓝牙后，可查看兼容的已配对设备。": "Allow Bluetooth access to see compatible paired devices.",
        "允许蓝牙访问": "Allow Bluetooth Access",
        "未允许蓝牙访问。": "Bluetooth access is not allowed.",
        "蓝牙访问受到系统限制。": "Bluetooth access is restricted.",
        "蓝牙权限设置…": "Bluetooth Privacy Settings…",
        "蓝牙当前不可用。": "Bluetooth is unavailable.",
        "没有可显示的已配对设备。": "No compatible paired devices found.",
        "请在系统设置中打开蓝牙。": "Turn on Bluetooth in System Settings.",
        "连接": "Connect",
        "断开": "Disconnect",
        "连接中…": "Connecting…",
        "断开中…": "Disconnecting…",
        "处理中…": "Working…",
        "断开后，此设备将暂时无法控制电脑。": "Once disconnected, this device will no longer control your Mac.",
        "取消": "Cancel",
        "确认断开": "Confirm Disconnect",
        "请在蓝牙设置中操作": "Manage in Bluetooth Settings",
        "耳机": "Headphones",
        "扬声器": "Speaker",
        "鼠标": "Mouse",
        "键盘": "Keyboard",
        "触控板": "Trackpad",
        "游戏控制器": "Controller",
        "电脑": "Computer",
        "蓝牙设备": "Bluetooth device",
        "未找到 Wi-Fi 接口": "No Wi-Fi interface found.",
        "未能更改 Wi-Fi 状态，请打开系统设置": "Could not change Wi-Fi power. Try Wi-Fi Settings.",
        "需要定位权限才能显示网络名称": "Location access is needed to show the network name.",
        "定位服务不可用": "Location services are unavailable.",
        "设备已连接": "Device connected.",
        "设备已断开": "Device disconnected.",
        "设备已不在配对列表中": "This device is no longer paired.",
        "请在系统蓝牙设置中管理此设备": "Manage this device in Bluetooth Settings.",
        "蓝牙连接失败": "Could not connect. Check that the device is on and nearby, then try again.",
        "蓝牙断开失败": "Could not disconnect. Try again or open Bluetooth Settings.",
        "未能确认设备连接状态": "Could not confirm the device’s connection. Refresh to check again.",
        "蓝牙不可用": "Bluetooth is unavailable."
    ]
}
