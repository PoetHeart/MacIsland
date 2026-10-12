import AppKit
import SwiftUI

@main
struct FrameworkChecks {
    @MainActor
    static func main() async throws {
        let plain = ScreenGeometry(frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080), safeHeight: 0, left: nil, right: nil)
        precondition(!plain.hasNotch && plain.centerX == -960 && plain.top == 1280)
        precondition(plain.panelFrame.maxY == 1280)
        let notched = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeHeight: 32,
                                    left: CGRect(x: 0, y: 924, width: 645.5, height: 32),
                                    right: CGRect(x: 824.5, y: 924, width: 645.5, height: 32))
        precondition(notched.hasNotch && notched.centerX == 735 && notched.notchSize == CGSize(width: 179, height: 32))
        let fallback = ScreenGeometry(frame: plain.screenFrame, safeHeight: 32, left: nil, right: nil)
        precondition(!fallback.hasNotch)
        for geometry in [plain, notched, fallback] {
            let idle = geometry.size(for: .idle)
            let compact = geometry.size(for: .compact)
            let expanded = geometry.size(for: .expanded)
            precondition(idle.width < compact.width && compact.width < expanded.width)
            precondition(idle.height < compact.height && compact.height < expanded.height)
            let path = IslandOutline().path(in: CGRect(origin: .zero, size: expanded))
            precondition(path.contains(CGPoint(x: expanded.width / 2, y: expanded.height / 2)))
            precondition(!path.contains(CGPoint(x: 1, y: expanded.height - 1)))
            precondition(!path.contains(CGPoint(x: expanded.width + 1, y: 20)))
        }
        print("PASS: notch geometry, external display offsets, fallback, state sizing and transparent corner hit testing")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var mouse = CGPoint(x: -10000, y: -10000)
        let controller = IslandWindowController(pointerLocation: { mouse })
        controller.show()
        guard let geometry = controller.model?.geometry else { fatalError("No screen available") }
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.model?.state == .idle && controller.panel?.ignoresMouseEvents == true)
        mouse = CGPoint(x: geometry.centerX, y: geometry.top - geometry.size(for: .idle).height + 2)
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.model?.state == .compact && controller.panel?.ignoresMouseEvents == false)
        try await Task.sleep(for: .milliseconds(800))
        precondition(controller.model?.state == .expanded)
        let expected = geometry.size(for: .expanded)
        precondition(abs(controller.displaySize.width - expected.width) < 1 && abs(controller.displaySize.height - expected.height) < 1,
                     "Animated hit region must follow rendered size")
        mouse = CGPoint(x: -10000, y: -10000)
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.panel?.ignoresMouseEvents == true)
        try await Task.sleep(for: .milliseconds(800))
        precondition(controller.model?.state == .idle)
        let idle = geometry.size(for: .idle)
        precondition(abs(controller.displaySize.width - idle.width) < 1)
        // Hide while expansion is pending; reopening must reset to idle.
        mouse = CGPoint(x: geometry.centerX, y: geometry.top - 2)
        try await Task.sleep(for: .milliseconds(70))
        controller.hide()
        try await Task.sleep(for: .milliseconds(250))
        precondition(controller.panel?.isVisible == false)
        mouse = CGPoint(x: -10000, y: -10000)
        controller.show()
        precondition(controller.model?.state == .idle && controller.panel?.isVisible == true)
        controller.hide()
        print("PASS: hover transitions, animated hit dimensions, click-through, cancellation, hide and show")
    }
}
