import Foundation

enum WindowAction: String, CaseIterable, Identifiable {
    case left, fill, tile, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: return "左半屏"
        case .fill: return "铺满屏幕"
        case .tile: return "魔法平铺"
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
        case .fill, .tile: return area
        }
    }

    static func tiles(count: Int, in area: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns = min(count, max(1, Int(ceil(sqrt(Double(count))))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            let cells = min(columns, count - row * columns)
            let x = area.minX + floor(CGFloat(column) * area.width / CGFloat(cells))
            let nextX = area.minX + floor(CGFloat(column + 1) * area.width / CGFloat(cells))
            let y = area.minY + floor(CGFloat(row) * area.height / CGFloat(rows))
            let nextY = area.minY + floor(CGFloat(row + 1) * area.height / CGFloat(rows))
            return CGRect(x: x, y: y, width: nextX - x, height: nextY - y)
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
    func visibleWindows(pid: Int32) throws -> [Window]
    func frame(of window: Window) throws -> CGRect
    func isAdjustable(_ window: Window) -> Bool
    func setFrame(_ frame: CGRect, of window: Window) throws
}

enum WindowActionError: LocalizedError {
    case unavailable, unsupported, noScreen, timedOut
    var errorDescription: String? {
        switch self {
        case .unavailable: return "未找到可控制的窗口，请先选中一个应用窗口。"
        case .unsupported: return "此窗口不支持调整，或处于全屏模式。"
        case .timedOut: return "目标应用响应较慢，请稍后重试。"
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
        let windows: [Access.Window]
        if action == .tile {
            windows = try access.visibleWindows(pid: pid).filter { window in
                guard access.isAdjustable(window), let frame = try? access.frame(of: window) else { return false }
                return WindowLayout.screenIndex(for: frame, screens: screens) == screenIndex
                    && !WindowLayout.approximatelyEqual(frame, screen.frame)
            }
            guard !windows.isEmpty else { throw WindowActionError.unavailable }
            guard windows.count <= 12 else {
                return WindowActionResult(applied: 0, failed: windows.count, message: "窗口超过 12 个，请先减少可见窗口后再平铺。")
            }
        } else {
            windows = [focused]
        }
        let frames = action == .tile ? WindowLayout.tiles(count: windows.count, in: screen.visibleFrame)
            : [WindowLayout.frame(for: action, in: screen.visibleFrame)]
        var applied = 0
        let deadline = Date().addingTimeInterval(5)
        for (window, frame) in zip(windows, frames) {
            guard Date() < deadline else { break }
            do {
                try access.setFrame(frame, of: window)
                if WindowLayout.approximatelyEqual(try access.frame(of: window), frame) { applied += 1 }
            } catch { /* Continue and accurately report partial completion. */ }
        }
        let failed = windows.count - applied
        let message = failed == 0 ? (action == .tile ? "已平铺 \(applied) 个窗口" : "已完成\(action.title)")
            : "\(applied) 个完成，\(failed) 个未完整调整（尺寸限制或应用不支持）"
        return WindowActionResult(applied: applied, failed: failed, message: message)
    }
}
