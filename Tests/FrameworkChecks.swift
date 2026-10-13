import AppKit
import SwiftUI

@main
struct FrameworkChecks {
    @MainActor
    static func main() async throws {
        try checkWindowActions()
        let plain = ScreenGeometry(frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080), safeHeight: 0, left: nil, right: nil)
        precondition(!plain.hasNotch && plain.centerX == -960 && plain.top == 1280)
        precondition(plain.panelFrame.maxY == 1280)
        let notched = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeHeight: 32,
                                    left: CGRect(x: 0, y: 924, width: 645.5, height: 32),
                                    right: CGRect(x: 824.5, y: 924, width: 645.5, height: 32))
        precondition(notched.hasNotch && notched.centerX == 735 && notched.notchSize == CGSize(width: 179, height: 32))
        precondition(notched.size(for: .idle) == notched.notchSize)
        precondition(plain.size(for: .idle).height == 0)
        precondition(notched.activationRect.minY == notched.top - notched.notchSize.height - 2)
        precondition(plain.activationRect.height == 4)
        precondition(!plain.activationRect.contains(CGPoint(x: plain.centerX, y: plain.top - 10)))
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

        let external = DisplayOption(id: "external", name: "External", hasNotch: false)
        let laptop = DisplayOption(id: "laptop", name: "Laptop", hasNotch: true)
        precondition(DisplayCatalog.resolve(selection: "automatic", options: [external, laptop]) == "laptop")
        precondition(DisplayCatalog.resolve(selection: "primary", options: [external, laptop]) == "external")
        precondition(DisplayCatalog.resolve(selection: "external", options: [external, laptop]) == "external")
        precondition(DisplayCatalog.resolve(selection: "external", options: [laptop]) == "laptop")
        precondition(DisplayCatalog.resolve(selection: "external", options: []) == nil)
        print("PASS: explicit screen selection, primary display, disconnect fallback and empty display list")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var mouse = CGPoint(x: -10000, y: -10000)
        let suite = "MacIsland.Checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = IslandSettings(defaults: defaults)
        precondition(settings.centerRatio == 0.6)
        settings.centerRatio = 0.75
        precondition(IslandSettings(defaults: defaults).centerRatio == 0.75)
        settings.displaySelection = "external"
        settings.hoverDelay = 0.3
        settings.animationsEnabled = false
        let restored = IslandSettings(defaults: defaults)
        precondition(restored.displaySelection == "external" && restored.hoverDelay == 0.3 && !restored.animationsEnabled)
        defaults.set(-10, forKey: "hoverDelay")
        precondition(IslandSettings(defaults: defaults).hoverDelay == 0.1)
        settings.displaySelection = "automatic"
        settings.hoverDelay = 0.18
        settings.animationsEnabled = true
        let controller = IslandWindowController(settings: settings, pointerLocation: { mouse })
        defer { controller.shutdown() }
        print("PASS: preference persistence and invalid delay clamping")
        controller.show()
        guard let geometry = controller.model?.geometry else { fatalError("No screen available") }
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.model?.state == .idle && controller.panel?.ignoresMouseEvents == true)
        mouse = CGPoint(x: geometry.centerX, y: geometry.activationRect.midY)
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.model?.state == .compact && controller.panel?.ignoresMouseEvents == false)
        try await Task.sleep(for: .milliseconds(800))
        precondition(controller.model?.state == .expanded)
        let expected = geometry.size(for: .expanded)
        precondition(abs(controller.displaySize.width - expected.width) < 1 && abs(controller.displaySize.height - expected.height) < 1,
                     "Animated hit region must follow rendered size")
        // Re-enter during the collapse grace period; the expanded panel must not shrink.
        mouse = CGPoint(x: -10000, y: -10000)
        try await Task.sleep(for: .milliseconds(70))
        mouse = CGPoint(x: geometry.centerX, y: geometry.top - 10)
        try await Task.sleep(for: .milliseconds(70))
        precondition(controller.model?.state == .expanded, "Quick re-entry must preserve expanded state")
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
        try await Task.sleep(for: .milliseconds(150))
        precondition(!IslandSettings(defaults: defaults).isVisible)
        settings.hoverDelay = 0.4
        try await Task.sleep(for: .milliseconds(150))
        precondition(controller.panel?.isVisible == false, "Changing settings must not reveal a hidden island")
        settings.hoverEnabled = false
        controller.show()
        mouse = CGPoint(x: geometry.centerX, y: geometry.top - 10)
        try await Task.sleep(for: .milliseconds(400))
        precondition(controller.model?.state == .idle && controller.panel?.ignoresMouseEvents == true)
        settings.hoverEnabled = true
        settings.animationsEnabled = false
        mouse = CGPoint(x: -10000, y: -10000)
        try await Task.sleep(for: .milliseconds(200))
        precondition(controller.model?.animationsEnabled == false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        settings.hoverDelay = 0.2
        try await Task.sleep(for: .milliseconds(150))
        precondition(controller.panel?.isVisible == false, "Settings must not show windows during sleep")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(controller.panel?.isVisible == true)
        controller.hide()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(controller.panel?.isVisible == false)
        print("PASS: live settings, disabled hover, persisted visibility, sleep/wake visibility and quick re-entry")
        print("PASS: hover transitions, animated hit dimensions, click-through, cancellation, hide and show")
    }
}
