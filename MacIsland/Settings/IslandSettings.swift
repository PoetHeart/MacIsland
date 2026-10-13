import Foundation
import Combine

@MainActor
final class IslandSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    func text(_ source: String) -> String { AppText.text(source, language: language) }
    @Published var displaySelection: String { didSet { defaults.set(displaySelection, forKey: "displaySelection") } }
    @Published var isVisible: Bool { didSet { defaults.set(isVisible, forKey: "islandVisible") } }
    @Published var hoverEnabled: Bool { didSet { defaults.set(hoverEnabled, forKey: "hoverEnabled") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: "animationsEnabled") } }

    @Published var centerRatio: Double { didSet { defaults.set(centerRatio, forKey: "centerRatio") } }
    var effectiveCenterRatio: Double { WindowLayout.normalizedCenterRatio(centerRatio) }

    var effectiveHoverDelay: Double { hoverDelay.isFinite ? min(0.8, max(0.1, hoverDelay)) : 0.18 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["displaySelection": "automatic", "islandVisible": true,
                                     "hoverEnabled": true, "hoverDelay": 0.18, "animationsEnabled": true, "centerRatio": 0.6])
        let savedLanguage = defaults.string(forKey: "language") ?? AppText.defaultLanguage
        language = ["zh-Hans", "en"].contains(savedLanguage) ? savedLanguage : AppText.defaultLanguage
        displaySelection = defaults.string(forKey: "displaySelection") ?? "automatic"
        isVisible = defaults.bool(forKey: "islandVisible")
        hoverEnabled = defaults.bool(forKey: "hoverEnabled")
        let delay = defaults.double(forKey: "hoverDelay")
        hoverDelay = delay.isFinite ? min(0.8, max(0.1, delay)) : 0.18
        animationsEnabled = defaults.bool(forKey: "animationsEnabled")
        centerRatio = WindowLayout.normalizedCenterRatio(defaults.double(forKey: "centerRatio"))
    }
}

/// Explicit language selection, shared by SwiftUI, AppKit menus and action feedback.
enum AppText {
    static var defaultLanguage: String {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh-Hans" : "en"
    }
    static let english: [String: String] = [
        "显示": "Display",
        "显示灵动岛": "Show Island",
        "所在显示器": "Display selection",
        "自动（优先刘海屏）": "Automatic (prefer notch)",
        "主显示器": "Primary display",
        "（刘海屏）": " (notched)",
        "已选显示器未连接": "Selected display disconnected",
        "暂时使用自动选择的屏幕，重新连接后恢复原选择。": "Using an available display until the selected one reconnects.",
        "窗口居中": "Center Window",
        "窗口比例": "Window size",
        "居中窗口宽高比例": "Centered window width and height",
        "宽、高各占屏幕可用区域的所选比例，默认 60%。": "Width and height each use this percentage of the usable screen. Default: 60%.",
        "交互": "Interaction",
        "鼠标悬停时展开": "Expand on hover",
        "展开等待": "Hover delay",
        "展开等待时间": "Hover delay",
        " 秒": " s",
        "启用弹性动画": "Spring animation",
        "同时遵循系统的“减少动态效果”设置。": "Also respects the system Reduce Motion preference.",
        "设置自动保存，下次启动时恢复。": "Preferences are saved automatically.",
        "设置…": "Settings…",
        "窗口控制授权…": "Window Control Permission…",
        "隐藏灵动岛": "Hide Island",
        "退出 MacIsland": "Quit MacIsland",
        "MacIsland 设置": "MacIsland Settings",
        "语言": "Language",
        "左半屏": "Left Half",
        "铺满屏幕": "Fill Screen",
        "居中": "Center",
        "右半屏": "Right Half",
        "先选中要调整的应用窗口": "Select an app window first",
        "当前应用": "Current app",
        "已获得窗口控制权限": "Window control is authorized",
        "请在系统设置 → 隐私与安全性 → 辅助功能中开启 MacIsland": "Enable MacIsland in System Settings → Privacy & Security → Accessibility.",
        "请先开启辅助功能权限": "Enable Accessibility permission first",
        "当前应用已改变，请确认目标后再点击": "The active app changed. Check the target and click again.",
        "正在调整…": "Adjusting…",
        "未找到可控制的窗口，请先选中一个应用窗口。": "No controllable window found. Select an app window first.",
        "此窗口不支持调整，或处于全屏模式。": "This window cannot be resized or is full screen.",
        "显示器已断开，请重新选择窗口。": "The display disconnected. Select a window again.",
        "窗口未完整调整（尺寸限制或应用不支持）": "Could not fully resize (size limits or unsupported app).",
        "开启窗口控制 · 需要辅助功能权限": "Enable window control · Accessibility required",
        "请在系统设置的“辅助功能”中开启 MacIsland": "Enable MacIsland in Accessibility settings",
        "已完成": "Done: ",
        "调整当前应用窗口：": "Adjust the active window: "
    ]
    static func text(_ source: String, language: String) -> String {
        language == "en" ? english[source] ?? source : source
    }
}
