import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(settings: delegate.settings, displays: delegate.displays) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { delegate.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
