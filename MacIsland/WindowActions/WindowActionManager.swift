import AppKit
import ApplicationServices
import Combine

@MainActor
final class WindowActionManager: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var targetName = ""
    @Published private(set) var message = ""
    @Published private(set) var isBusy = false
    @Published private(set) var isWindowDrag = false
    @Published var dragSelection: WindowAction?
    private var dragToken: UUID?
    private var samplePending = false
    private var lastSample = Date.distantPast
    var isTrackingDrag: Bool { dragToken != nil }
    private let worker = WindowActionWorker()
    private var targetPID: pid_t?
    private let queue = DispatchQueue(label: "com.macisland.window-actions", qos: .userInitiated)

    private let settings: IslandSettings
    init(settings: IslandSettings) {
        self.settings = settings
        targetName = settings.text("先选中要调整的应用窗口")
    }
    func text(_ source: String) -> String { settings.text(source) }

    var canPerform: Bool { isTrusted && targetPID != nil && !isBusy }

    func captureTarget() {
        isTrusted = AXIsProcessTrusted()
        guard !isBusy, !isTrackingDrag else { return }
        message = ""
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else {
            targetPID = nil
            targetName = text("先选中要调整的应用窗口")
            return
        }
        targetPID = app.processIdentifier
        targetName = app.localizedName ?? text("当前应用")
    }

    func requestPermission() {
        // Triggered only by an explicit click; granting remains a system-controlled user action.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        message = isTrusted ? text("已获得窗口控制权限") : text("请在系统设置 → 隐私与安全性 → 辅助功能中开启 MacIsland")
    }

    func perform(_ action: WindowAction) {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else { message = text("请先开启辅助功能权限"); return }
        guard !isBusy, let pid = targetPID else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            captureTarget()
            message = text("当前应用已改变，请确认目标后再点击")
            return
        }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            WindowScreen(frame: WindowLayout.accessibilityRect($0.frame, primaryTop: primaryTop),
                         visibleFrame: WindowLayout.accessibilityRect($0.visibleFrame, primaryTop: primaryTop))
        }
        let language = settings.language
        let centerRatio = settings.effectiveCenterRatio
        isBusy = true
        message = text("正在调整…")
        let worker = self.worker
        queue.async { [weak self] in
            let result: String
            do {
                let outcome = try worker.executor
                    .perform(action, pid: pid, screens: screens, centerRatio: centerRatio)
                result = outcome.restored ? AppText.text("已恢复原窗口", language: language) : outcome.applied == 1
                    ? AppText.text("已完成", language: language) + AppText.text(action.title, language: language)
                    : AppText.text(outcome.message, language: language)
            } catch { result = AppText.text(error.localizedDescription, language: language) }
            DispatchQueue.main.async {
                self?.message = result
                self?.isBusy = false
            }
        }
    }

    private func axPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }

    func beginDrag(at point: CGPoint) {
        cancelDrag()
        isTrusted = AXIsProcessTrusted()
        guard isTrusted, !isBusy else { return }
        let token = UUID()
        dragToken = token
        let point = axPoint(point)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let worker = self.worker
        queue.async {
            guard let (window, pid) = worker.access.windowUnderPointer(point), pid != ownPID,
                  let frame = try? worker.access.frame(of: window) else { return }
            worker.drag = WindowActionWorker.Drag(token: token, window: window, pid: pid, frame: frame, start: point)
        }
    }

    func sampleDrag(at point: CGPoint) {
        guard let token = dragToken, !samplePending, Date().timeIntervalSince(lastSample) >= 0.08 else { return }
        samplePending = true
        lastSample = Date()
        let point = axPoint(point)
        let worker = self.worker
        queue.async { [weak self] in
            var accepted = false
            var pid: pid_t?
            if var drag = worker.drag, drag.token == token,
               let current = try? worker.access.frame(of: drag.window) {
                if abs(current.width - drag.frame.width) < 3 && abs(current.height - drag.frame.height) < 3 {
                    drag.confirmed = drag.confirmed || WindowDragGeometry.isWindowMove(original: drag.frame, current: current, start: drag.start, pointer: point)
                    worker.drag = drag
                    accepted = drag.confirmed
                    pid = drag.pid
                } else { worker.drag = nil }
            }
            DispatchQueue.main.async {
                guard let self, self.dragToken == token else { return }
                self.samplePending = false
                if self.isWindowDrag != accepted { self.isWindowDrag = accepted }
                if accepted, let pid {
                    self.targetPID = pid
                    self.targetName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? self.text("当前应用")
                }
            }
        }
    }

    func cancelDrag() {
        dragToken = nil
        samplePending = false
        isWindowDrag = false
        dragSelection = nil
        let worker = self.worker
        queue.async { worker.drag = nil }
    }

    func finishDrag(action: WindowAction?, destination: CGRect) {
        guard let token = dragToken else { return }
        dragToken = nil
        samplePending = false
        isWindowDrag = false
        dragSelection = nil
        let worker = self.worker
        guard let action, !isBusy, AXIsProcessTrusted() else {
            queue.async { worker.drag = nil }
            return
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            WindowScreen(frame: WindowLayout.accessibilityRect($0.frame, primaryTop: primaryTop),
                         visibleFrame: WindowLayout.accessibilityRect($0.visibleFrame, primaryTop: primaryTop))
        }
        let targetScreen = WindowLayout.accessibilityRect(destination, primaryTop: primaryTop)
        let ratio = settings.effectiveCenterRatio
        let language = settings.language
        isBusy = true
        queue.async { [weak self] in
            var message = AppText.text("拖动已取消", language: language)
            defer { worker.drag = nil }
            if let drag = worker.drag, drag.token == token, drag.confirmed, drag.pid == frontPID {
                do {
                    let focused = try worker.access.focusedWindow(pid: drag.pid)
                    guard worker.access.sameWindow(focused, drag.window) else { throw WindowActionError.unavailable }
                    let result = try worker.executor.perform(action, pid: drag.pid, screens: screens,
                        centerRatio: ratio, window: drag.window, originalFrame: drag.frame, destination: targetScreen, toggle: false)
                    message = result.applied == 1 ? AppText.text("已完成", language: language) + AppText.text(action.title, language: language)
                        : AppText.text(result.message, language: language)
                } catch { message = AppText.text(error.localizedDescription, language: language) }
            }
            DispatchQueue.main.async {
                self?.message = message
                self?.isBusy = false
            }
        }
    }

}


/// All mutable AX handles and restoration history are confined to the serial action queue.
private final class WindowActionWorker: @unchecked Sendable {
    let access = AccessibilityWindowAccess()
    lazy var executor = WindowActionExecutor(access: access)
    struct Drag {
        let token: UUID
        let window: AXUIElement
        let pid: pid_t
        let frame: CGRect
        let start: CGPoint
        var confirmed = false
    }
    var drag: Drag?
}
