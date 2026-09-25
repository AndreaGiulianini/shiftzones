import AppKit
import ApplicationServices

/// Private but stable API (used by Rectangle, yabai, Hammerspoon): the CGWindowID of an AX window.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (if the permission hasn't been granted yet).
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A window of another application, read and moved through the Accessibility API.
struct AXWindow {
    let element: AXUIElement

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    /// Frame in AX coordinates.
    var frame: CGRect? {
        guard let origin = element.point(of: kAXPositionAttribute), let size = element.size(of: kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    func setFrame(_ frame: CGRect) {
        withEnhancedUserInterfaceDisabled {
            guard isResizable else {
                // Fixed-size window: center it in the zone.
                if let size = self.frame?.size {
                    setPosition(CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
                }
                return
            }
            // Position → size → position: when moving to another display the size
            // would otherwise be clamped by the display the window comes from.
            setPosition(frame.origin)
            setSize(frame.size)
            setPosition(frame.origin)
        }
    }

    func setPosition(_ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    /// With "AXEnhancedUserInterface" enabled (VoiceOver, some apps) resizes are animated
    /// and often stop halfway: turn it off for the duration of the change.
    private func withEnhancedUserInterfaceDisabled(_ body: () -> Void) {
        guard let pid else { body(); return }
        let app = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let enabled = AXUIElementCopyAttributeValue(app, attribute, &value) == .success && (value as? Bool) == true
        if enabled { AXUIElementSetAttributeValue(app, attribute, kCFBooleanFalse) }
        body()
        if enabled { AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue) }
    }
}

extension AXWindow: Hashable {
    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

extension AXWindow {
    /// Window of another app under the given point (AX coordinates).
    static func under(_ point: CGPoint) -> AXWindow? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
           let hit, let window = window(containing: hit) {
            return window.pid == ownPID ? nil : window
        }
        return fromWindowList(at: point, excluding: ownPID)
    }

    private static func window(containing element: AXUIElement) -> AXWindow? {
        var current: AXUIElement? = element
        for _ in 0..<32 {
            guard let element = current else { return nil }
            if element.string(of: kAXRoleAttribute) == kAXWindowRole { return AXWindow(element: element) }
            if let window = element.element(of: kAXWindowAttribute) { return AXWindow(element: window) }
            current = element.element(of: kAXParentAttribute)
        }
        return nil
    }

    /// Fallback for apps that don't answer AXUIElementCopyElementAtPosition properly.
    private static func fromWindowList(at point: CGPoint, excluding ownPID: pid_t) -> AXWindow? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.contains(point)
            else { continue }
            let number = info[kCGWindowNumber as String] as? CGWindowID
            let windows = AXUIElementCreateApplication(pid).elements(of: kAXWindowsAttribute).map { AXWindow(element: $0) }
            return windows.first { $0.windowID == number } ?? windows.first { $0.frame == bounds }
        }
        return nil
    }
}

private extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
    }

    func string(of name: String) -> String? {
        attribute(name) as? String
    }

    func element(of name: String) -> AXUIElement? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    func elements(of name: String) -> [AXUIElement] {
        guard let values = attribute(name) as? [AnyObject] else { return [] }
        return values.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeBitCast($0, to: AXUIElement.self) : nil
        }
    }

    func point(of name: String) -> CGPoint? {
        var point = CGPoint.zero
        return axValue(of: name).map { AXValueGetValue($0, .cgPoint, &point) } == true ? point : nil
    }

    func size(of name: String) -> CGSize? {
        var size = CGSize.zero
        return axValue(of: name).map { AXValueGetValue($0, .cgSize, &size) } == true ? size : nil
    }

    private func axValue(of name: String) -> AXValue? {
        guard let value = attribute(name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }
}
