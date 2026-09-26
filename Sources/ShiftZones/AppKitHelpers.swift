import AppKit

extension NSApplication {
    /// Brings this menu bar app to the front, e.g. to give the editor keyboard focus.
    func bringToFront() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
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
