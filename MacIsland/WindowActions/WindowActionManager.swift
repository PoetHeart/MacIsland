import AppKit
import ApplicationServices
import Combine

@MainActor
final class WindowActionManager: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var targetName = "先选中要调整的应用窗口"
    @Published private(set) var message = ""
    @Published private(set) var isBusy = false
    private var targetPID: pid_t?
    private let queue = DispatchQueue(label: "com.macisland.window-actions", qos: .userInitiated)

    var canPerform: Bool { isTrusted && targetPID != nil && !isBusy }

    func captureTarget() {
        isTrusted = AXIsProcessTrusted()
        guard !isBusy else { return }
        message = ""
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else {
            targetPID = nil
            targetName = "先选中要调整的应用窗口"
            return
        }
        targetPID = app.processIdentifier
        targetName = app.localizedName ?? "当前应用"
    }

    func requestPermission() {
        // Triggered only by an explicit click; granting remains a system-controlled user action.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        message = isTrusted ? "已获得窗口控制权限" : "请在系统设置 → 隐私与安全性 → 辅助功能中开启 MacIsland"
    }

    func perform(_ action: WindowAction) {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else { message = "请先开启辅助功能权限"; return }
        guard !isBusy, let pid = targetPID else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            captureTarget()
            message = "当前应用已改变，请确认目标后再点击"
            return
        }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            WindowScreen(frame: WindowLayout.accessibilityRect($0.frame, primaryTop: primaryTop),
                         visibleFrame: WindowLayout.accessibilityRect($0.visibleFrame, primaryTop: primaryTop))
        }
        isBusy = true
        message = "正在调整…"
        queue.async { [weak self] in
            let result: String
            do {
                result = try WindowActionExecutor(access: AccessibilityWindowAccess())
                    .perform(action, pid: pid, screens: screens).message
            } catch { result = error.localizedDescription }
            DispatchQueue.main.async {
                self?.message = result
                self?.isBusy = false
            }
        }
    }
}
