import Foundation

public struct ResizeEdges: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1 << 0)
    public static let right = ResizeEdges(rawValue: 1 << 1)
    public static let top = ResizeEdges(rawValue: 1 << 2)
    public static let bottom = ResizeEdges(rawValue: 1 << 3)
}

public enum SplitOrientation: Sendable {
    /// Two zones side by side.
    case columns
    /// Two zones stacked vertically.
    case rows
}

/// Editor operations. All values are normalized; `threshold` is the distance within which edges snap.
public enum ZoneEditing {
    /// Edges closer than this are treated as the same line.
    static let linkTolerance = 0.002

    /// Moves a zone by (dx, dy), snapping its edges to the other zones' edges and to the 0, ½, 1 lines.
    public static func move(_ id: UUID, in zones: [Zone], dx: Double, dy: Double,
                            threshold: (x: Double, y: Double)) -> [Zone] {
        zones.map { zone in
            guard zone.id == id else { return zone }
            let others = zones.filter { $0.id != id }
            var rect = zone.rect
            rect.x = snapSpan(start: rect.x + dx, length: rect.width, to: guides(others, .x), threshold: threshold.x)
            rect.y = snapSpan(start: rect.y + dy, length: rect.height, to: guides(others, .y), threshold: threshold.y)
            rect.x = min(max(rect.x, 0), 1 - rect.width)
            rect.y = min(max(rect.y, 0), 1 - rect.height)
            return Zone(id: id, rect: rect)
        }
    }

    /// Resizes a zone by dragging its edges. With `linked`, edges shared with other zones move
    /// together (like grid dividers); screen edges are never linked.
    public static func resize(_ id: UUID, in zones: [Zone], edges: ResizeEdges, dx: Double, dy: Double,
                              linked: Bool, threshold: (x: Double, y: Double),
                              minSize: (width: Double, height: Double)) -> [Zone] {
        var result = zones
        if edges.contains(.left) {
            result = moveEdge(result, id: id, axis: .x, leading: true, delta: dx, linked: linked, threshold: threshold.x, minLength: minSize.width)
        }
        if edges.contains(.right) {
            result = moveEdge(result, id: id, axis: .x, leading: false, delta: dx, linked: linked, threshold: threshold.x, minLength: minSize.width)
        }
        if edges.contains(.top) {
            result = moveEdge(result, id: id, axis: .y, leading: true, delta: dy, linked: linked, threshold: threshold.y, minLength: minSize.height)
        }
        if edges.contains(.bottom) {
            result = moveEdge(result, id: id, axis: .y, leading: false, delta: dy, linked: linked, threshold: threshold.y, minLength: minSize.height)
        }
        return result
    }

    public static func split(_ zone: Zone, _ orientation: SplitOrientation) -> [Zone] {
        let r = zone.rect
        switch orientation {
        case .columns:
            let mid = r.minX + r.width / 2
            return [Zone(id: zone.id, rect: .edges(minX: r.minX, minY: r.minY, maxX: mid, maxY: r.maxY)),
                    Zone(rect: .edges(minX: mid, minY: r.minY, maxX: r.maxX, maxY: r.maxY))]
        case .rows:
            let mid = r.minY + r.height / 2
            return [Zone(id: zone.id, rect: .edges(minX: r.minX, minY: r.minY, maxX: r.maxX, maxY: mid)),
                    Zone(rect: .edges(minX: r.minX, minY: mid, maxX: r.maxX, maxY: r.maxY))]
        }
    }

    // MARK: - Implementation

    enum Axis { case x, y }

    private static func moveEdge(_ zones: [Zone], id: UUID, axis: Axis, leading: Bool, delta: Double,
                                 linked: Bool, threshold: Double, minLength: Double) -> [Zone] {
        guard let target = zones.first(where: { $0.id == id }) else { return zones }
        let line = leading ? target.rect.start(axis) : target.rect.end(axis)
        let isScreenBorder = line < linkTolerance || line > 1 - linkTolerance
        let shouldLink = linked && !isScreenBorder

        // Zones that start on this line and zones that end on it.
        var starting: Set<UUID> = [], ending: Set<UUID> = []
        for zone in zones {
            if zone.id == id {
                if leading { starting.insert(id) } else { ending.insert(id) }
            } else if shouldLink {
                if abs(zone.rect.start(axis) - line) < linkTolerance { starting.insert(zone.id) }
                if abs(zone.rect.end(axis) - line) < linkTolerance { ending.insert(zone.id) }
            }
        }

        // No affected zone may shrink below the minimum size.
        var lower = 0.0, upper = 1.0
        for zone in zones {
            if starting.contains(zone.id) { upper = min(upper, zone.rect.end(axis) - minLength) }
            if ending.contains(zone.id) { lower = max(lower, zone.rect.start(axis) + minLength) }
        }
        guard lower <= upper else { return zones }

        let affected = starting.union(ending)
        var value = line + delta
        if let snapped = nearest(value, in: guides(zones.filter { !affected.contains($0.id) }, axis), threshold: threshold) {
            value = snapped
        }
        value = min(max(value, lower), upper)

        return zones.map { zone in
            var zone = zone
            if starting.contains(zone.id) { zone.rect.setStart(axis, value) }
            if ending.contains(zone.id) { zone.rect.setEnd(axis, value) }
            return zone
        }
    }

    private static func guides(_ zones: [Zone], _ axis: Axis) -> [Double] {
        [0, 0.5, 1] + zones.flatMap { [$0.rect.start(axis), $0.rect.end(axis)] }
    }

    private static func nearest(_ value: Double, in candidates: [Double], threshold: Double) -> Double? {
        candidates
            .filter { abs($0 - value) <= threshold }
            .min { abs($0 - value) < abs($1 - value) }
    }

    /// Snaps the start or the end of the segment, whichever needs the smaller shift.
    private static func snapSpan(start: Double, length: Double, to candidates: [Double], threshold: Double) -> Double {
        let fromStart = nearest(start, in: candidates, threshold: threshold)
        let fromEnd = nearest(start + length, in: candidates, threshold: threshold).map { $0 - length }
        switch (fromStart, fromEnd) {
        case let (a?, b?): return abs(a - start) <= abs(b - start) ? a : b
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return start
        }
    }
}

extension ZoneRect {
    func start(_ axis: ZoneEditing.Axis) -> Double { axis == .x ? minX : minY }
    func end(_ axis: ZoneEditing.Axis) -> Double { axis == .x ? maxX : maxY }

    /// Moves the leading edge, keeping the trailing one in place.
    mutating func setStart(_ axis: ZoneEditing.Axis, _ value: Double) {
        switch axis {
        case .x: self = .edges(minX: value, minY: minY, maxX: maxX, maxY: maxY)
        case .y: self = .edges(minX: minX, minY: value, maxX: maxX, maxY: maxY)
        }
    }

    /// Moves the trailing edge, keeping the leading one in place.
    mutating func setEnd(_ axis: ZoneEditing.Axis, _ value: Double) {
        switch axis {
        case .x: self = .edges(minX: minX, minY: minY, maxX: value, maxY: maxY)
        case .y: self = .edges(minX: minX, minY: minY, maxX: maxX, maxY: value)
        }
    }
}
