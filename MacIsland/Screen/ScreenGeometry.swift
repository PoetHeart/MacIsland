import AppKit

/// All coordinates come from NSScreen in global desktop points, including negative origins.
struct ScreenGeometry {
    let screenFrame: CGRect
    let centerX: CGFloat
    let top: CGFloat
    let notchSize: CGSize
    let hasNotch: Bool

    init(screen: NSScreen) {
        self.init(frame: screen.frame, safeHeight: screen.safeAreaInsets.top,
                  left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
    }

    init(frame: CGRect, safeHeight: CGFloat, left: CGRect?, right: CGRect?) {
        screenFrame = frame
        top = frame.maxY
        if safeHeight > 0,
           let left,
           let right,
           right.minX > left.maxX {
            centerX = (left.maxX + right.minX) / 2
            notchSize = CGSize(width: right.minX - left.maxX, height: safeHeight)
            hasNotch = true
        } else {
            centerX = frame.midX
            notchSize = .zero
            hasNotch = false
        }
    }

    static func preferredScreen() -> NSScreen? {
        // Prefer a physical notch; lid-closed and external-only setups fall back naturally.
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    func size(for state: IslandState) -> CGSize {
        let idleWidth = hasNotch ? notchSize.width + 12 : 132
        let idleHeight = hasNotch ? notchSize.height + 5 : 28
        let requested: CGSize
        switch state {
        case .idle: requested = CGSize(width: idleWidth, height: idleHeight)
        case .compact: requested = CGSize(width: max(idleWidth + 96, 252), height: max(idleHeight + 20, 52))
        case .expanded: requested = CGSize(width: max(idleWidth + 200, 440), height: max(notchSize.height + 154, 186))
        }
        // Dimensions are design choices; screen position and cutout dimensions are never hard-coded.
        return CGSize(width: min(requested.width, screenFrame.width - 24),
                      height: min(requested.height, screenFrame.height - 24))
    }

    var panelFrame: CGRect {
        let expanded = size(for: .expanded)
        // Extra room permits spring overshoot without clipping.
        let width = min(expanded.width + 100, screenFrame.width)
        let height = min(expanded.height + 80, screenFrame.height)
        return CGRect(x: centerX - width / 2, y: top - height, width: width, height: height)
    }
}
