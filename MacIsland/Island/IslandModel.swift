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
    init(geometry: ScreenGeometry) { self.geometry = geometry }
}
