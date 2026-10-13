# MacIsland

**Window controls, tucked into your Mac’s notch.** A native macOS toolbar that stays invisible until you hover at the top of the screen.

**[简体中文](README.md) · English**

[Download DMG](https://github.com/PoetHeart/MacIsland/releases/latest) · [Release notes](https://github.com/PoetHeart/MacIsland/releases) · [Report an issue](https://github.com/PoetHeart/MacIsland/issues)

## Features

- **Left Half, Fill Screen, Center and Right Half** for the active application window, without stealing focus.
- **Adjustable centering:** width and height each default to 60% of usable screen space; adjust from 30% to 100%.
- **Invisible when idle:** hover over the notch or top-center edge to reveal controls; move away to collapse.
- **Multiple displays:** automatic notch preference or explicit selection, with disconnect fallback and reconnection recovery.
- **Chinese / English:** choose your language in Settings → Language / 语言. Changes apply immediately and are saved.
- **Smooth transitions:** interruptible springs, stable button layout and separate fades. Supports Reduce Motion.

Built with Swift, SwiftUI and AppKit using public Apple APIs. No third-party dependencies. No music, battery, stashing or automatic tiling features.

## Download and install

1. Download `MacIsland-0.4.0-universal.dmg` from [GitHub Releases](https://github.com/PoetHeart/MacIsland/releases/latest).
2. Open it and drag **MacIsland.app** into **Applications**.
3. Launch MacIsland from Applications. Use the capsule menu-bar icon for settings, visibility and quitting.
4. For window actions, choose **Window Control Permission…** and manually enable MacIsland in System Settings → Privacy & Security → Accessibility.

Requires **macOS 14.0 or later**. The app is universal for Apple Silicon and Intel. Runtime checks were performed on Apple Silicon; Intel was compile-tested only.

**Signing:** this release is ad-hoc signed, without Developer ID signing or Apple notarization. Gatekeeper may block a downloaded copy. Please understand this limitation before installing; building from source with Xcode is another option. SHA-256 checksums are provided with the release.

## How it works

Select a target app window, then hover over the notch or top-center edge. On displays without a notch, the invisible trigger is approximately 132 × 4 points. Transparent areas pass clicks through.

Fill Screen uses the work area outside the menu bar and Dock; it does not enter a separate full-screen Space. Minimum window sizes, full-screen state and app restrictions can prevent resizing; failures are reported. Hover detection requires no permission. Window actions need Accessibility permission, but not Screen Recording.

## Development

Open `MacIsland.xcodeproj`. Run `./Tests/run-checks.sh` for regression checks, or `./scripts/release-dmg.sh` to create the universal app, DMG and checksum file.

Checks cover window geometry, display fallback, saved settings, both languages, transparent triggers, exact top-edge activation and interrupted animations. Third-party window operations are tested with a mock adapter; app compatibility, display hot-plugging and Intel runtime behavior still need hardware testing.

See [development notes (Chinese)](docs/DEVELOPMENT.md) for architecture details.
