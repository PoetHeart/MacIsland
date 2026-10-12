import AppKit
import Combine

struct DisplayOption: Identifiable, Equatable {
    let id: String
    let name: String
    let hasNotch: Bool
}

@MainActor
final class DisplayCatalog: ObservableObject {
    @Published private(set) var options: [DisplayOption] = []

    init() {
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() {
        options = NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = Self.identifier(for: screen) else { return nil }
            return DisplayOption(id: id, name: "\(screen.localizedName) · \(index + 1)", hasNotch: screen.safeAreaInsets.top > 0)
        }
    }

    static func identifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Shared resolver is testable without physically connecting extra displays.
    static func resolve(selection: String, options: [DisplayOption]) -> String? {
        if selection == "primary" { return options.first?.id }
        if let selected = options.first(where: { $0.id == selection }) { return selected.id }
        return options.first(where: \.hasNotch)?.id ?? options.first?.id
    }

    static func screen(for selection: String) -> NSScreen? {
        let screens = NSScreen.screens
        let options = screens.compactMap { screen -> DisplayOption? in
            guard let id = identifier(for: screen) else { return nil }
            return DisplayOption(id: id, name: screen.localizedName, hasNotch: screen.safeAreaInsets.top > 0)
        }
        let selectedID = resolve(selection: selection, options: options)
        return screens.first { identifier(for: $0) == selectedID } ?? ScreenGeometry.preferredScreen()
    }
}
