import AppKit
import ApplicationServices

/// Used only on the dedicated window-action queue, never on the SwiftUI rendering thread.
struct AccessibilityWindowAccess: WindowAccess {
    typealias Window = AXUIElement

    private func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ attribute: String, of source: AXUIElement) -> AXUIElement? {
        guard let raw = value(attribute, of: source), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func app(pid: Int32) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        return app
    }

    func focusedWindow(pid: Int32) throws -> AXUIElement {
        guard let window = element(kAXFocusedWindowAttribute, of: app(pid: pid)) else { throw WindowActionError.unavailable }
        AXUIElementSetMessagingTimeout(window, 0.2)
        return window
    }

    func visibleWindows(pid: Int32) throws -> [AXUIElement] {
        guard let windows = value(kAXWindowsAttribute, of: app(pid: pid)) as? [AXUIElement] else {
            throw WindowActionError.unavailable
        }
        // CG supplies on-screen bounds without requiring window titles or screen recording permission.
        // Reject ambiguous identical bounds to avoid moving an off-Space window by mistake.
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visibleBounds = info.compactMap { row -> CGRect? in
            guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        guard windows.count <= 48 else { throw WindowActionError.timedOut }
        let deadline = Date().addingTimeInterval(2)
        var candidates: [(AXUIElement, CGRect)] = []
        for window in windows {
            guard Date() < deadline else { throw WindowActionError.timedOut }
            AXUIElementSetMessagingTimeout(window, 0.2)
            if isAdjustable(window), let rect = try? frame(of: window) { candidates.append((window, rect)) }
        }
        return candidates.compactMap { window, rect in
            let matchCount = candidates.filter { WindowLayout.approximatelyEqual($0.1, rect) }.count
            let visibleCount = visibleBounds.filter { WindowLayout.approximatelyEqual($0, rect) }.count
            return visibleCount >= matchCount ? window : nil
        }
    }

    func frame(of window: AXUIElement) throws -> CGRect {
        guard let position = value(kAXPositionAttribute, of: window), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(kAXSizeAttribute, of: window), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowActionError.unavailable
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { throw WindowActionError.unavailable }
        return CGRect(origin: point, size: dimensions)
    }

    func isAdjustable(_ window: AXUIElement) -> Bool {
        guard value(kAXSubroleAttribute, of: window) as? String == kAXStandardWindowSubrole,
              value(kAXMinimizedAttribute, of: window) as? Bool == false else { return false }
        var position = DarwinBoolean(false)
        var size = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &position) == .success
            && AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &size) == .success
            && position.boolValue && size.boolValue
    }

    func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        var point = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else {
            throw WindowActionError.unsupported
        }
        // Moving first lets the target display impose its constraints; re-position after resizing.
        guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success,
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success,
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success else {
            throw WindowActionError.unsupported
        }
    }
}
