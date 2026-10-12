import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
