import SwiftUI

struct WindowToolbar: View {
    @ObservedObject var manager: WindowActionManager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(manager.isWindowDrag ? WindowDragGeometry.actions : WindowAction.allCases) { action in
                    Button { manager.perform(action) } label: {
                        VStack(spacing: 12) {
                            WindowActionIcon(action: action).frame(width: 28, height: 19)
                            Text(manager.text(action.title)).font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).frame(height: 76)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(WindowTileStyle())
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(manager.dragSelection == action ? Color.accentColor : .clear, lineWidth: 2))
                    .disabled(!manager.canPerform)
                    .help(manager.text("调整当前应用窗口：") + manager.text(action.title))
                }
            }
            if manager.isWindowDrag {
                Text(manager.text(manager.dragSelection == nil ? "拖到按钮上，松手应用；移出取消" : "松手应用所选布局"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
            } else if !manager.isTrusted {
                Button(manager.message.isEmpty ? manager.text("开启窗口控制 · 需要辅助功能权限") : manager.text("请在系统设置的“辅助功能”中开启 MacIsland")) { manager.requestPermission() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
            } else {
                Text(manager.message.isEmpty ? manager.targetName : manager.message)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct WindowTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration)
    }
    private struct Tile: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.35))
                .background(.white.opacity(configuration.isPressed ? 0.24 : hovering && enabled ? 0.18 : 0.065), in: RoundedRectangle(cornerRadius: 10))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

private struct WindowActionIcon: View {
    let action: WindowAction
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.7)
                switch action {
                case .left:
                    Rectangle().frame(width: (width - 6) / 2, height: height - 6).padding(.leading, 3)
                case .right:
                    Rectangle().frame(width: (width - 6) / 2, height: height - 6).offset(x: width / 2, y: 0)
                case .center:
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: width * 0.5, height: height * 0.5)
                        .offset(x: width * 0.25)
                case .fill:
                    RoundedRectangle(cornerRadius: 1).padding(3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
