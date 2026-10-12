import SwiftUI

enum IslandState: String {
    case idle = "Idle"
    case compact = "Compact"
    case expanded = "Expanded"
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var state: IslandState = .idle
    @Published var geometry: ScreenGeometry
    let animationsEnabled: Bool
    init(geometry: ScreenGeometry, animationsEnabled: Bool = true) {
        self.geometry = geometry
        self.animationsEnabled = animationsEnabled
    }
}
