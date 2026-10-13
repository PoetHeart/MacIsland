import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = IslandSettings()
    let displays = DisplayCatalog()
    private var settingsWindow: SettingsWindowController?
    private var island: IslandWindowController!
    private var languageSubscription: AnyCancellable?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        island = IslandWindowController(settings: settings)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "MacIsland")
        rebuildMenu()
        languageSubscription = settings.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.rebuildMenu()
        }
        if settings.isVisible { island.show() }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "MacIsland · V0.5.1", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(openSettings), key: ","))
        menu.addItem(item("窗口控制授权…", #selector(authorizeWindowControl)))
        menu.addItem(.separator())
        menu.addItem(item("显示灵动岛", #selector(showIsland)))
        menu.addItem(item("隐藏灵动岛", #selector(hideIsland)))
        menu.addItem(.separator())
        menu.addItem(item("退出 MacIsland", #selector(quit), key: "q"))
        statusItem.menu = menu
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
    func applicationWillTerminate(_ notification: Notification) { island.shutdown() }
}
