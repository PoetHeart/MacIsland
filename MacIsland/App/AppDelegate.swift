import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandWindowController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        island = IslandWindowController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "MacIsland")
        rebuildMenu()
        island.show()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "MacIsland · V0.1", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item("显示灵动岛", #selector(showIsland)))
        menu.addItem(item("隐藏灵动岛", #selector(hideIsland)))
        menu.addItem(.separator())
        menu.addItem(item("退出 MacIsland", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showIsland() { island.show() }
    @objc private func hideIsland() { island.hide() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { island.hide() }
}
