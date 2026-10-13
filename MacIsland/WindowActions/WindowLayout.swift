import Foundation

enum WindowAction: String, CaseIterable, Identifiable {
    case left, fill, center, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: return "左半屏"
        case .fill: return "铺满屏幕"
        case .center: return "居中"
        case .right: return "右半屏"
        }
    }
}

struct WindowScreen {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum WindowLayout {
    /// Accessibility uses a top-left origin; AppKit uses bottom-left. The primary display defines zero.
    static func accessibilityRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Convert through the same AX layout calculation used when the drag is released.
    static func previewFrame(for action: WindowAction, visibleFrame: CGRect,
                             primaryTop: CGFloat, centerRatio: Double) -> CGRect {
        let area = accessibilityRect(visibleFrame, primaryTop: primaryTop)
        return accessibilityRect(frame(for: action, in: area, centerRatio: centerRatio), primaryTop: primaryTop)
    }

    static func screenIndex(for frame: CGRect, screens: [WindowScreen]) -> Int? {
        screens.indices.max { a, b in
            intersectionArea(frame, screens[a].frame) < intersectionArea(frame, screens[b].frame)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    static func normalizedCenterRatio(_ ratio: Double) -> Double {
        ratio.isFinite ? min(1, max(0.3, ratio)) : 0.6
    }

    static func frame(for action: WindowAction, in area: CGRect, centerRatio: Double = 0.6) -> CGRect {
        let half = floor(area.width / 2)
        switch action {
        case .left: return CGRect(x: area.minX, y: area.minY, width: half, height: area.height)
        case .right: return CGRect(x: area.minX + half, y: area.minY, width: area.width - half, height: area.height)
        case .fill: return area
        case .center:
            let ratio = normalizedCenterRatio(centerRatio)
            let width = floor(area.width * ratio)
            let height = floor(area.height * ratio)
            return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
        }
    }

    static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}

protocol WindowAccess {
    associatedtype Window
    func sameWindow(_ lhs: Window, _ rhs: Window) -> Bool
    func focusedWindow(pid: Int32) throws -> Window
    func frame(of window: Window) throws -> CGRect
    func isAdjustable(_ window: Window) -> Bool
    func setFrame(_ frame: CGRect, of window: Window) throws
}

enum WindowActionError: LocalizedError {
    case unavailable, unsupported, noScreen
    var errorDescription: String? {
        switch self {
        case .unavailable: return "未找到可控制的窗口，请先选中一个应用窗口。"
        case .unsupported: return "此窗口不支持调整，或处于全屏模式。"
        case .noScreen: return "显示器已断开，请重新选择窗口。"
        }
    }
}

struct WindowActionResult {
    let applied: Int
    let failed: Int
    let message: String
    var restored = false
}

final class WindowActionExecutor<Access: WindowAccess> {
    let access: Access
    init(access: Access) { self.access = access }
    private struct SavedLayout {
        let pid: Int32
        let window: Access.Window
        let original: CGRect
        let applied: CGRect
        let action: WindowAction
    }
    private var history: [SavedLayout] = []

    func perform(_ action: WindowAction, pid: Int32, screens: [WindowScreen], centerRatio: Double = 0.6,
                 window: Access.Window? = nil, originalFrame: CGRect? = nil,
                 destination: CGRect? = nil, toggle: Bool = true) throws -> WindowActionResult {
        let focused = try window ?? access.focusedWindow(pid: pid)
        let original = try access.frame(of: focused)
        guard let screenIndex = WindowLayout.screenIndex(for: destination ?? original, screens: screens),
              (destination ?? original).intersects(screens[screenIndex].frame) else { throw WindowActionError.noScreen }
        let screen = screens[screenIndex]
        let previous = history.first { $0.pid == pid && access.sameWindow($0.window, focused) }
        let knownLayout = previous.map { WindowLayout.approximatelyEqual(original, $0.applied) } ?? false
        guard access.isAdjustable(focused), knownLayout || !WindowLayout.approximatelyEqual(original, screen.frame) else {
            throw WindowActionError.unsupported
        }
        let desired = WindowLayout.frame(for: action, in: screen.visibleFrame, centerRatio: centerRatio)
        let unchanged = previous.map { WindowLayout.approximatelyEqual(original, $0.applied) } ?? false
        let restore = toggle && unchanged && previous?.action == action
            && previous.map { WindowLayout.approximatelyEqual(desired, $0.applied) } == true
        let baseline = originalFrame ?? (unchanged ? previous!.original : original)
        let frame = restore ? WindowLayout.safeRestore(previous!.original, screens: screens, fallback: screen.visibleFrame) : desired
        try access.setFrame(frame, of: focused)
        let completed = WindowLayout.approximatelyEqual(try access.frame(of: focused), frame)
        if completed {
            history.removeAll { $0.pid == pid && access.sameWindow($0.window, focused) }
            if !restore {
                history.append(SavedLayout(pid: pid, window: focused, original: baseline, applied: frame, action: action))
                if history.count > 32 { history.removeFirst() }
            }
        }
        return WindowActionResult(applied: completed ? 1 : 0, failed: completed ? 0 : 1,
                                  message: completed ? (restore ? "已恢复原窗口" : "已完成\(action.title)") : "窗口未完整调整（尺寸限制或应用不支持）",
                                  restored: restore && completed)
    }
}

extension WindowLayout {
    static func safeRestore(_ rect: CGRect, screens: [WindowScreen], fallback: CGRect) -> CGRect {
        if screens.contains(where: { $0.visibleFrame.contains(rect) }) { return rect }
        let width = min(rect.width, fallback.width)
        let height = min(rect.height, fallback.height)
        return CGRect(x: min(max(rect.minX, fallback.minX), fallback.maxX - width),
                      y: min(max(rect.minY, fallback.minY), fallback.maxY - height), width: width, height: height)
    }
}

/// Pure geometry used by both drag detection and regression tests. All coordinates here use AX's top-left origin.
enum WindowDragGeometry {
    static func isWindowMove(original: CGRect, current: CGRect, start: CGPoint, pointer: CGPoint) -> Bool {
        let dx = current.minX - original.minX, dy = current.minY - original.minY
        let px = pointer.x - start.x, py = pointer.y - start.y
        return abs(current.width - original.width) < 3 && abs(current.height - original.height) < 3
            && hypot(dx, dy) >= 6 && hypot(px, py) >= 6
            && dx * px + dy * py > 0 && abs(dx - px) < 48 && abs(dy - py) < 48
    }

    static let actions: [WindowAction] = [.left, .center, .right]
    static func selection(at point: CGPoint, geometry: ScreenGeometry) -> WindowAction? {
        let width = geometry.size(for: .expanded).width
        let minX = geometry.centerX - width / 2 + 24
        let buttonWidth = (width - 48 - 16) / 3
        let bottom = geometry.top - (geometry.hasNotch ? geometry.notchSize.height + 14 : 18) - 76
        guard point.y >= bottom, point.y <= geometry.top else { return nil }
        for (index, action) in actions.enumerated() {
            let x = minX + CGFloat(index) * (buttonWidth + 8)
            if point.x >= x && point.x <= x + buttonWidth { return action }
        }
        return nil
    }
}
