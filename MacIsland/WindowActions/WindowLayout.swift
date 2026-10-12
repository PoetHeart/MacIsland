import Foundation

enum WindowAction: String, CaseIterable, Identifiable {
    case left, fill, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: return "左半屏"
        case .fill: return "铺满屏幕"
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

    static func screenIndex(for frame: CGRect, screens: [WindowScreen]) -> Int? {
        screens.indices.max { a, b in
            intersectionArea(frame, screens[a].frame) < intersectionArea(frame, screens[b].frame)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    static func frame(for action: WindowAction, in area: CGRect) -> CGRect {
        let half = floor(area.width / 2)
        switch action {
        case .left: return CGRect(x: area.minX, y: area.minY, width: half, height: area.height)
        case .right: return CGRect(x: area.minX + half, y: area.minY, width: area.width - half, height: area.height)
        case .fill: return area
        }
    }

    static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}

protocol WindowAccess {
    associatedtype Window
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
}

struct WindowActionExecutor<Access: WindowAccess> {
    let access: Access

    func perform(_ action: WindowAction, pid: Int32, screens: [WindowScreen]) throws -> WindowActionResult {
        let focused = try access.focusedWindow(pid: pid)
        let original = try access.frame(of: focused)
        guard let screenIndex = WindowLayout.screenIndex(for: original, screens: screens),
              original.intersects(screens[screenIndex].frame) else { throw WindowActionError.noScreen }
        let screen = screens[screenIndex]
        guard access.isAdjustable(focused), !WindowLayout.approximatelyEqual(original, screen.frame) else {
            throw WindowActionError.unsupported
        }
        let frame = WindowLayout.frame(for: action, in: screen.visibleFrame)
        try access.setFrame(frame, of: focused)
        let completed = WindowLayout.approximatelyEqual(try access.frame(of: focused), frame)
        return WindowActionResult(applied: completed ? 1 : 0, failed: completed ? 0 : 1,
                                  message: completed ? "已完成\(action.title)" : "窗口未完整调整（尺寸限制或应用不支持）")
    }
}
