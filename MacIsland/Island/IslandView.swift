import SwiftUI

/// A single shared outline drives both drawing and pointer hit testing.
struct IslandOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = min(9, rect.height / 2)
        let bottom: CGFloat = min(24, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        p.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Reports interpolated spring dimensions, so transparent corners and animation space pass clicks through.
private struct IslandSurface: AnimatableModifier {
    var width: CGFloat
    var height: CGFloat
    let reportSize: (CGSize) -> Void
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
    func body(content: Content) -> some View {
        let size = CGSize(width: width, height: height)
        content
            .frame(width: max(1, width), height: max(1, height))
            .background(.black, in: IslandOutline())
            .clipShape(IslandOutline())
            .onChange(of: size, initial: true) { _, value in reportSize(value) }
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var windowActions: WindowActionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let reportSize: (CGSize) -> Void

    var body: some View {
        let size = model.geometry.size(for: model.state)
        ZStack(alignment: .top) {
            Color.clear
            content
                .modifier(IslandSurface(width: size.width, height: size.height, reportSize: reportSize))
                .opacity(model.state == .idle ? 0 : 1)
                .allowsHitTesting(model.state != .idle)
                .accessibilityHidden(model.state == .idle)
                .animation(!model.animationsEnabled ? nil : reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.82), value: model.state)
        }
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(spacing: 12) {
            // Keep all labels below the physical camera housing.
            Spacer(minLength: model.geometry.hasNotch ? model.geometry.notchSize.height + 8 : 8)
            if model.state == .compact {
                Text("MacIsland").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .transition(.opacity)
            } else if model.state == .expanded {
                WindowToolbar(manager: windowActions)
                Spacer(minLength: 12)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MacIsland，\(model.state.rawValue)")
    }
}
