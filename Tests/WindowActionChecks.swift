import Foundation

private final class FakeWindow {
    var frame: CGRect
    var adjustable: Bool
    var refusesResize = false
    init(_ frame: CGRect, adjustable: Bool = true) { self.frame = frame; self.adjustable = adjustable }
}

private struct FakeAccess: WindowAccess {
    var windows: [FakeWindow]
    func focusedWindow(pid: Int32) throws -> FakeWindow {
        guard let first = windows.first else { throw WindowActionError.unavailable }
        return first
    }
    func visibleWindows(pid: Int32) throws -> [FakeWindow] { windows }
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
    for count in 1...12 {
        let frames = WindowLayout.tiles(count: count, in: area)
        precondition(frames.count == count)
        precondition(frames.allSatisfy { area.contains($0) })
        precondition(frames.reduce(0) { $0 + $1.width * $1.height } == area.width * area.height)
        for i in frames.indices {
            for j in frames.indices where j > i {
                let overlap = frames[i].intersection(frames[j])
                precondition(overlap.isNull || overlap.width == 0 || overlap.height == 0)
            }
        }
    }
    for action in [WindowAction.left, .fill, .right] {
        let window = FakeWindow(CGRect(x: -1600, y: 0, width: 800, height: 600))
        let result = try WindowActionExecutor(access: FakeAccess(windows: [window])).perform(action, pid: 1, screens: [primary, external])
        precondition(result.applied == 1 && result.failed == 0)
        precondition(window.frame == WindowLayout.frame(for: action, in: external.visibleFrame))
    }
    let a = FakeWindow(CGRect(x: 20, y: 50, width: 600, height: 500))
    let b = FakeWindow(CGRect(x: 100, y: 70, width: 600, height: 500))
    let c = FakeWindow(CGRect(x: -1500, y: 0, width: 600, height: 500))
    let fixed = FakeWindow(CGRect(x: 200, y: 200, width: 200, height: 100), adjustable: false)
    let originalC = c.frame
    let tiled = try WindowActionExecutor(access: FakeAccess(windows: [a, b, c, fixed])).perform(.tile, pid: 1, screens: [primary, external])
    precondition(tiled.applied == 2 && c.frame == originalC && fixed.frame.width == 200)
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
    print("PASS: window actions, negative-origin coordinate conversion, odd-width split, tiling coverage, screen isolation, fixed/fullscreen windows and size constraints")
}
