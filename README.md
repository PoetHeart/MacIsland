# MacIsland

**把窗口管理放进 Mac 的刘海。** 原生 macOS 悬浮工具栏，平时隐形，鼠标移到屏幕顶部即可展开。

**简体中文 · [English](README.en.md)**

[下载最新版 DMG](https://github.com/PoetHeart/MacIsland/releases/latest) · [功能与更新记录](https://github.com/PoetHeart/MacIsland/releases) · [反馈问题](https://github.com/PoetHeart/MacIsland/issues)

## 你可以做什么

- **左半屏、铺满屏幕、居中、右半屏**：快速整理当前应用窗口，不抢走目标应用焦点。
- **可调居中大小**：默认宽、高各为屏幕可用区域的 60%，可在 30%–100% 之间调整并保存。
- **不凸出的灵动岛**：默认完全透明，移入刘海或屏幕顶部中央展开，移开后连续收起。
- **适配多显示器**：自动优先刘海屏，也可指定显示器；断开后回退，重连后恢复。
- **中英文切换**：在设置的 Language / 语言 中选择简体中文或 English，即时生效并保存。
- **更自然的动画**：可中断弹簧、稳定的按钮布局和独立淡入淡出；遵循系统“减少动态效果”。

Swift + SwiftUI + AppKit，公开 Apple API，无第三方依赖。没有音乐、电池、收进或魔法平铺功能。

## 下载与安装

1. 从 [GitHub Releases](https://github.com/PoetHeart/MacIsland/releases/latest) 下载 `MacIsland-0.4.0-universal.dmg`。
2. 打开 DMG，将 **MacIsland.app** 拖到 **Applications**。
3. 从“应用程序”启动 MacIsland。菜单栏胶囊图标提供设置、显示、隐藏和退出。
4. 要控制其他应用窗口，点击“窗口控制授权…”，在系统设置的“隐私与安全性 → 辅助功能”中手动允许 MacIsland。

**系统要求：macOS 14.0 或更新。** DMG 包含 Apple Silicon / Intel 通用应用；本次在 Apple Silicon 上完成运行检查，Intel 仅完成编译检查。

**签名说明：** 当前为 ad-hoc 签名，尚未使用 Developer ID 签名或经过 Apple 公证，下载后可能被 Gatekeeper 阻止。请在安装前了解此限制；也可使用 Xcode 从源码构建。发布页提供 SHA-256 校验文件。

## 使用说明

选择目标应用窗口，然后把鼠标移到刘海或屏幕顶部中央。无刘海屏幕的触发区为顶部中央约 132 × 4 点；透明区不拦截点击。

“铺满屏幕”使用菜单栏和 Dock 之外的可用区域，不进入独立全屏 Space。窗口的最小尺寸、全屏状态及应用自身限制可能阻止调整；界面会反馈失败。基础悬停无需权限，窗口控制仅需辅助功能权限，不需要录屏权限。

## 开发与验证

打开 `MacIsland.xcodeproj` 即可开发，运行 `./Tests/run-checks.sh` 执行回归检查。执行 `./scripts/release-dmg.sh` 构建通用应用并生成 DMG 与校验文件。

测试覆盖分屏和居中坐标、多屏回退、设置持久化、中英文、透明触发区、最上沿触发及反复打断动画。第三方窗口操作使用模拟适配器验证；不同应用、显示器热插拔及 Intel 实机表现仍需实测。

更多架构与测试说明见 [开发文档](docs/DEVELOPMENT.md)。
