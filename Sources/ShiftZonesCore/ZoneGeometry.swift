import CoreGraphics

/// Conversions between normalized zones and absolute coordinates (top-left origin).
public enum ZoneGeometry {
    /// The zone's drop area, without spacing: used to find which zone is under the cursor.
    public static func hitFrame(of rect: ZoneRect, in area: CGRect) -> CGRect {
        CGRect(x: area.minX + CGFloat(rect.x) * area.width,
               y: area.minY + CGFloat(rect.y) * area.height,
               width: CGFloat(rect.width) * area.width,
               height: CGFloat(rect.height) * area.height)
    }

    /// Frame the window will get: the margin from the screen edges and the gap between adjacent zones are both `spacing`.
    public static func windowFrame(of rect: ZoneRect, in area: CGRect, spacing: Double) -> CGRect {
        let half = CGFloat(max(spacing, 0) / 2)
        let frame = hitFrame(of: rect, in: area.insetBy(dx: half, dy: half)).insetBy(dx: half, dy: half)
        let minX = frame.minX.rounded(), minY = frame.minY.rounded()
        return CGRect(x: minX, y: minY, width: frame.maxX.rounded() - minX, height: frame.maxY.rounded() - minY)
    }

    /// Zone under the point; when zones overlap, the smallest one wins.
    public static func zone(at point: CGPoint, in zones: [Zone], area: CGRect) -> Zone? {
        zones
            .filter { hitFrame(of: $0.rect, in: area).contains(point) }
            .min { $0.rect.area < $1.rect.area }
    }

    /// Zones covered by the rectangle from `anchor` to `current`, grown until it fully
    /// contains every zone it touches (like combining zones in FancyZones).
    public static func span(from anchor: Zone, to current: Zone, in zones: [Zone]) -> [Zone] {
        var bounds = anchor.rect.union(current.rect)
        var selected: [Zone] = []
        while true {
            let next = zones.filter { bounds.overlaps($0.rect) }
            if next.count <= selected.count { return selected.isEmpty ? [anchor, current] : selected }
            selected = next
            bounds = next.reduce(bounds) { $0.union($1.rect) }
        }
    }

    public static func boundingRect(of zones: [Zone]) -> ZoneRect? {
        guard let first = zones.first else { return nil }
        return zones.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }
}
