import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = IslandSettings()
    let displays = DisplayCatalog()
    private var settingsWindow: SettingsWindowController?
    private var island: IslandWindowController!
    private var languageSubscription: AnyCancellable?
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var connectivity: StatusPopoverController?
    private let systemStatus = SystemStatusMonitor()
    private var statusSubscription: AnyCancellable?
    private var statusRows: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        island = IslandWindowController(settings: settings)
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        connectivity = StatusPopoverController(settings: settings, status: systemStatus) { [weak self] in
            self?.openSettings()
        }
        statusSubscription = systemStatus.$snapshot.removeDuplicates().sink { [weak self] snapshot in
            self?.updateStatus(snapshot)
        }
        rebuildMenu()
        languageSubscription = settings.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.rebuildMenu()
        }
        systemStatus.start()
        if settings.isVisible { island.show() }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "MacIsland · V0.7.0", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusRows = (0..<3).map { _ in
            let row = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
            return row
        }
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(openSettings), key: ","))
        menu.addItem(item("窗口控制授权…", #selector(authorizeWindowControl)))
        menu.addItem(.separator())
        menu.addItem(item("显示灵动岛", #selector(showIsland)))
        menu.addItem(item("隐藏灵动岛", #selector(hideIsland)))
        menu.addItem(.separator())
        menu.addItem(item("退出 MacIsland", #selector(quit), key: "q"))
        statusMenu = menu
        updateStatus(systemStatus.snapshot)
    }

    private func updateStatus(_ snapshot: SystemStatusSnapshot) {
        let lines = StatusPresentation.lines(for: snapshot, language: settings.language)
        for (row, line) in zip(statusRows, lines) { row.title = line }
        let summary = (["MacIsland"] + lines).joined(separator: "\n")
        statusItem.button?.image = StatusIconRenderer.image(for: snapshot)
        statusItem.button?.toolTip = summary
        statusItem.button?.setAccessibilityLabel(summary.replacingOccurrences(of: "\n", with: ", "))
    }

    func menuWillOpen(_ menu: NSMenu) { systemStatus.refresh() }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            connectivity?.close()
            statusItem.menu = statusMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            connectivity?.toggle(relativeTo: sender)
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: settings.text(title), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: settings, displays: displays) }
        settingsWindow?.present()
    }
    @objc private func authorizeWindowControl() { island.requestWindowControlPermission() }
    @objc private func showIsland() { island.show() }
    @objc private func hideIsland() { island.hide() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        connectivity?.shutdown()
        systemStatus.stop()
        statusSubscription = nil
        island.shutdown()
    }
}
