import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(settings: delegate.settings, displays: delegate.displays) }
            .commands { IslandCommands(settings: delegate.settings, openSettings: delegate.openSettings) }
    }
}

private struct IslandCommands: Commands {
    @ObservedObject var settings: IslandSettings
    let openSettings: () -> Void
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(settings.text("设置…"), action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
