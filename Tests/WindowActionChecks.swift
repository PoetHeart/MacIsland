import Foundation

private final class FakeWindow {
    var frame: CGRect
    var adjustable: Bool
    var refusesResize = false
    init(_ frame: CGRect, adjustable: Bool = true) { self.frame = frame; self.adjustable = adjustable }
}

private struct FakeAccess: WindowAccess {
    var windows: [FakeWindow]
    func sameWindow(_ lhs: FakeWindow, _ rhs: FakeWindow) -> Bool { lhs === rhs }
    func focusedWindow(pid: Int32) throws -> FakeWindow {
        guard let first = windows.first else { throw WindowActionError.unavailable }
        return first
    }
    func frame(of window: FakeWindow) throws -> CGRect { window.frame }
    func isAdjustable(_ window: FakeWindow) -> Bool { window.adjustable }
    func setFrame(_ frame: CGRect, of window: FakeWindow) throws {
        if !window.refusesResize { window.frame = frame }
    }
}

func checkWindowActions() throws {
    let primary = WindowScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                               visibleFrame: CGRect(x: 0, y: 32, width: 1440, height: 810))
    let external = WindowScreen(frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: -1920, y: -155, width: 1920, height: 1000))
    precondition(WindowLayout.accessibilityRect(CGRect(x: -1920, y: 0, width: 1920, height: 1080), primaryTop: 900) == external.frame)
    let area = CGRect(x: -1001, y: 25, width: 1001, height: 700)
    let left = WindowLayout.frame(for: .left, in: area)
    let right = WindowLayout.frame(for: .right, in: area)
    precondition(left.width + right.width == area.width && left.maxX == right.minX && right.maxX == area.maxX)
    for ratio in [0.3, 0.6, 0.85, 1.0] {
        let centered = WindowLayout.frame(for: .center, in: area, centerRatio: ratio)
        precondition(centered.midX == area.midX && centered.midY == area.midY)
        precondition(centered.width == floor(area.width * ratio) && centered.height == floor(area.height * ratio))
    }
    precondition(WindowLayout.normalizedCenterRatio(.nan) == 0.6)
    precondition(WindowLayout.normalizedCenterRatio(0) == 0.3)
    precondition(WindowLayout.normalizedCenterRatio(2) == 1)
    let custom = FakeWindow(CGRect(x: -1600, y: 0, width: 800, height: 600))
    let customResult = try WindowActionExecutor(access: FakeAccess(windows: [custom]))
        .perform(.center, pid: 1, screens: [primary, external], centerRatio: 0.8)
    precondition(customResult.applied == 1)
    precondition(custom.frame == WindowLayout.frame(for: .center, in: external.visibleFrame, centerRatio: 0.8))
    for action in [WindowAction.left, .fill, .center, .right] {
        let window = FakeWindow(CGRect(x: -1600, y: 0, width: 800, height: 600))
        let result = try WindowActionExecutor(access: FakeAccess(windows: [window])).perform(action, pid: 1, screens: [primary, external])
        precondition(result.applied == 1 && result.failed == 0)
        precondition(window.frame == WindowLayout.frame(for: action, in: external.visibleFrame))
    }
    let fixed = FakeWindow(CGRect(x: 200, y: 200, width: 200, height: 100), adjustable: false)
    do {
        _ = try WindowActionExecutor(access: FakeAccess(windows: [fixed])).perform(.fill, pid: 1, screens: [primary])
        preconditionFailure("Fixed-size windows must not be resized")
    } catch WindowActionError.unsupported { }
    let b = FakeWindow(CGRect(x: 100, y: 70, width: 600, height: 500))
    b.refusesResize = true
    let limited = try WindowActionExecutor(access: FakeAccess(windows: [b])).perform(.fill, pid: 1, screens: [primary])
    precondition(limited.applied == 0 && limited.failed == 1)
    let fullScreen = FakeWindow(primary.frame)
    do {
        _ = try WindowActionExecutor(access: FakeAccess(windows: [fullScreen])).perform(.left, pid: 1, screens: [primary])
        preconditionFailure("Full-display windows must not be resized")
    } catch WindowActionError.unsupported { }
    do {
        _ = try WindowActionExecutor(access: FakeAccess(windows: [])).perform(.left, pid: 1, screens: [primary])
        preconditionFailure("Missing window must report failure")
    } catch WindowActionError.unavailable { }
    let initial = CGRect(x: 160, y: 100, width: 700, height: 500)
    let one = FakeWindow(initial)
    let two = FakeWindow(CGRect(x: 230, y: 150, width: 800, height: 540))
    let executor = WindowActionExecutor(access: FakeAccess(windows: [one, two]))
    _ = try executor.perform(.left, pid: 42, screens: [primary])
    let restored = try executor.perform(.left, pid: 42, screens: [primary])
    precondition(restored.restored && one.frame == initial)
    _ = try executor.perform(.left, pid: 42, screens: [primary])
    _ = try executor.perform(.center, pid: 42, screens: [primary])
    _ = try executor.perform(.center, pid: 42, screens: [primary])
    precondition(one.frame == initial, "Changing layouts must preserve the original baseline")
    let twoOriginal = two.frame
    _ = try executor.perform(.right, pid: 42, screens: [primary], window: two)
    precondition(one.frame == initial)
    _ = try executor.perform(.right, pid: 42, screens: [primary], window: two)
    precondition(two.frame == twoOriginal, "Restoration history is per window")
    _ = try executor.perform(.center, pid: 42, screens: [primary], centerRatio: 0.6)
    let changedRatio = try executor.perform(.center, pid: 42, screens: [primary], centerRatio: 0.8)
    precondition(!changedRatio.restored && one.frame.width == floor(primary.visibleFrame.width * 0.8))
    one.frame = initial.offsetBy(dx: 35, dy: 20)
    let manual = one.frame
    _ = try executor.perform(.right, pid: 42, screens: [primary])
    _ = try executor.perform(.right, pid: 42, screens: [primary])
    precondition(one.frame == manual, "Manual movement starts a fresh baseline")
    let originalOnExternal = CGRect(x: -1700, y: 0, width: 700, height: 500)
    one.frame = originalOnExternal.offsetBy(dx: 500, dy: 10)
    _ = try executor.perform(.left, pid: 42, screens: [primary, external], window: one,
                             originalFrame: originalOnExternal, destination: primary.frame, toggle: false)
    let dropRestored = try executor.perform(.left, pid: 42, screens: [primary, external])
    precondition(dropRestored.restored && one.frame == originalOnExternal)
    one.frame = originalOnExternal
    _ = try executor.perform(.left, pid: 42, screens: [primary, external])
    // The moved window is now on the primary display after an unplug.
    one.frame = WindowLayout.frame(for: .left, in: primary.visibleFrame)
    let safe = WindowLayout.safeRestore(originalOnExternal, screens: [primary], fallback: primary.visibleFrame)
    precondition(primary.visibleFrame.contains(safe))
    let point = CGPoint(x: initial.minX + 100, y: initial.minY + 20)
    precondition(WindowDragGeometry.isWindowMove(original: initial, current: initial.offsetBy(dx: 50, dy: -60), start: point, pointer: CGPoint(x: point.x + 50, y: point.y - 60)))
    precondition(!WindowDragGeometry.isWindowMove(original: initial, current: initial, start: point, pointer: CGPoint(x: point.x + 100, y: point.y)))
    precondition(!WindowDragGeometry.isWindowMove(original: initial, current: CGRect(x: initial.minX, y: initial.minY, width: 900, height: 500), start: point, pointer: CGPoint(x: point.x + 200, y: point.y)))
    let geometry = ScreenGeometry(frame: CGRect(x: -1440, y: 0, width: 1440, height: 900), safeHeight: 0, left: nil, right: nil)
    let zoneWidth = (geometry.size(for: .expanded).width - 64) / 3
    for (index, action) in WindowDragGeometry.actions.enumerated() {
        let x = geometry.centerX - geometry.size(for: .expanded).width / 2 + 24 + CGFloat(index) * (zoneWidth + 8) + zoneWidth / 2
        precondition(WindowDragGeometry.selection(at: CGPoint(x: x, y: geometry.top), geometry: geometry) == action)
    }
    precondition(WindowDragGeometry.selection(at: CGPoint(x: geometry.centerX, y: geometry.top - 200), geometry: geometry) == nil)
    print("PASS: per-window restore, changed layouts/ratios, manual movement, pre-drag restore, disconnected displays, false drag rejection and drop zones")
    print("PASS: window actions, negative-origin coordinate conversion, odd-width split, fixed/fullscreen windows and size constraints")
}
