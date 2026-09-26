import Foundation

/// Rectangle normalized (0...1) to the usable area of a display.
/// The origin is at the top-left, as in Accessibility API coordinates.
public struct ZoneRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = ZoneRect(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var area: Double { width * height }

    /// Rectangle defined by its four edges.
    public static func edges(minX: Double, minY: Double, maxX: Double, maxY: Double) -> ZoneRect {
        ZoneRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func union(_ other: ZoneRect) -> ZoneRect {
        .edges(minX: min(minX, other.minX), minY: min(minY, other.minY),
               maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }

    /// True only if the intersection has a positive area (two zones sharing an edge don't overlap).
    public func overlaps(_ other: ZoneRect, tolerance: Double = 1e-6) -> Bool {
        min(maxX, other.maxX) - max(minX, other.minX) > tolerance
            && min(maxY, other.maxY) - max(minY, other.minY) > tolerance
    }
}

public struct Zone: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var rect: ZoneRect

    public init(id: UUID = UUID(), rect: ZoneRect) {
        self.id = id
        self.rect = rect
    }
}

/// The zones of one display. An empty layout turns zones off on that display.
public struct ZoneLayout: Codable, Hashable, Sendable {
    public var zones: [Zone]

    public init(zones: [Zone] = []) {
        self.zones = zones
    }
}
