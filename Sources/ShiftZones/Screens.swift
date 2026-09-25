import AppKit
import ShiftZonesCore

// "AX" coordinates: origin at the top-left of the primary display, y pointing down.
// They are the ones used by the Accessibility API and CGWindowList; NSScreen/NSEvent
// use a bottom-left origin instead.

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable display identifier: survives reboots and display arrangement changes.
    var stableID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return "display-\(displayID)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var axFrame: CGRect { ScreenGeometry.toAX(frame) }

    /// Usable area (without menu bar and Dock) in AX coordinates.
    var axVisibleFrame: CGRect { ScreenGeometry.toAX(visibleFrame) }

    var aspectRatio: Double {
        visibleFrame.height > 0 ? Double(visibleFrame.width / visibleFrame.height) : 16.0 / 9
    }
}

enum ScreenGeometry {
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAX(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func mouseLocation() -> CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first { $0.axFrame.contains(point) }
            ?? screens.min { $0.axFrame.distance(to: point) < $1.axFrame.distance(to: point) }
    }

    static func screen(withID id: String) -> NSScreen? {
        NSScreen.screens.first { $0.stableID == id }
    }

    /// Displays in their physical arrangement: left to right, then top to bottom.
    static var screensLeftToRight: [NSScreen] {
        NSScreen.screens.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
    }

    static func connectedMonitors() -> [MonitorDescriptor] {
        let primary = NSScreen.screens.first
        return screensLeftToRight.map { screen in
            MonitorDescriptor(id: screen.stableID, name: screen.localizedName,
                              resolution: "\(Int(screen.frame.width)) × \(Int(screen.frame.height))",
                              isPrimary: screen == primary, aspectRatio: screen.aspectRatio)
        }
    }
}

extension LayoutStore {
    func layout(for screen: NSScreen) -> ZoneLayout {
        layout(forDisplay: screen.stableID, aspectRatio: screen.aspectRatio)
    }
}

extension CGRect {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - point.x, 0, point.x - maxX)
        let dy = Swift.max(minY - point.y, 0, point.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && size.isClose(to: other.size, tolerance: tolerance)
    }
}

extension CGSize {
    func isClose(to other: CGSize, tolerance: CGFloat = 2) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
