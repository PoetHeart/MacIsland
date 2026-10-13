import SwiftUI
import AppKit
import Combine

struct SettingsView: View {
    @ObservedObject var settings: IslandSettings
    @ObservedObject var displays: DisplayCatalog

    private var unavailableSelection: Bool {
        !["automatic", "primary"].contains(settings.displaySelection)
            && !displays.options.contains { $0.id == settings.displaySelection }
    }

    var body: some View {
        Form {
            Section(settings.text("语言")) {
                Picker("Language / 语言", selection: $settings.language) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
            }
            Section(settings.text("显示")) {
                Toggle(settings.text("显示灵动岛"), isOn: $settings.isVisible)
                Picker(settings.text("所在显示器"), selection: $settings.displaySelection) {
                    Text(settings.text("自动（优先刘海屏）")).tag("automatic")
                    Text(settings.text("主显示器")).tag("primary")
                    ForEach(displays.options) { option in
                        Text(option.name + (option.hasNotch ? settings.text("（刘海屏）") : "")).tag(option.id)
                    }
                    if unavailableSelection {
                        Text(settings.text("已选显示器未连接")).tag(settings.displaySelection)
                    }
                }
                if unavailableSelection {
                    Text(settings.text("暂时使用自动选择的屏幕，重新连接后恢复原选择。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(settings.text("窗口居中")) {
                HStack {
                    Text(settings.text("窗口比例"))
                    Slider(value: $settings.centerRatio, in: 0.3...1, step: 0.05)
                        .accessibilityLabel(settings.text("居中窗口宽高比例"))
                    Text(settings.effectiveCenterRatio.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Text(settings.text("宽、高各占屏幕可用区域的所选比例，默认 60%。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(settings.text("交互")) {
                Toggle(settings.text("鼠标悬停时展开"), isOn: $settings.hoverEnabled)
                HStack {
                    Text(settings.text("展开等待"))
                    Slider(value: $settings.hoverDelay, in: 0.1...0.8, step: 0.02)
                        .accessibilityLabel(settings.text("展开等待时间"))
                    Text(settings.effectiveHoverDelay.formatted(.number.precision(.fractionLength(2))) + settings.text(" 秒"))
                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                .disabled(!settings.hoverEnabled)
                Toggle(settings.text("启用弹性动画"), isOn: $settings.animationsEnabled)
                Text(settings.text("同时遵循系统的“减少动态效果”设置。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("MacIsland · V0.5.1").font(.headline)
                Text(settings.text("设置自动保存，下次启动时恢复。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 630)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private var languageSubscription: AnyCancellable?
    init(settings: IslandSettings, displays: DisplayCatalog) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 630),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = settings.text("MacIsland 设置")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, displays: displays))
        window.center()
        super.init(window: window)
        languageSubscription = settings.$language.receive(on: RunLoop.main).sink { [weak window] language in
            window?.title = AppText.text("MacIsland 设置", language: language)
        }
    }
    required init?(coder: NSCoder) { nil }
    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
