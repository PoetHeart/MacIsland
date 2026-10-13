import Foundation
import Combine

@MainActor
final class IslandSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var displaySelection: String { didSet { defaults.set(displaySelection, forKey: "displaySelection") } }
    @Published var isVisible: Bool { didSet { defaults.set(isVisible, forKey: "islandVisible") } }
    @Published var hoverEnabled: Bool { didSet { defaults.set(hoverEnabled, forKey: "hoverEnabled") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: "animationsEnabled") } }

    @Published var centerRatio: Double { didSet { defaults.set(centerRatio, forKey: "centerRatio") } }
    var effectiveCenterRatio: Double { WindowLayout.normalizedCenterRatio(centerRatio) }

    var effectiveHoverDelay: Double { hoverDelay.isFinite ? min(0.8, max(0.1, hoverDelay)) : 0.18 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["displaySelection": "automatic", "islandVisible": true,
                                     "hoverEnabled": true, "hoverDelay": 0.18, "animationsEnabled": true, "centerRatio": 0.6])
        displaySelection = defaults.string(forKey: "displaySelection") ?? "automatic"
        isVisible = defaults.bool(forKey: "islandVisible")
        hoverEnabled = defaults.bool(forKey: "hoverEnabled")
        let delay = defaults.double(forKey: "hoverDelay")
        hoverDelay = delay.isFinite ? min(0.8, max(0.1, delay)) : 0.18
        animationsEnabled = defaults.bool(forKey: "animationsEnabled")
        centerRatio = WindowLayout.normalizedCenterRatio(defaults.double(forKey: "centerRatio"))
    }
}
