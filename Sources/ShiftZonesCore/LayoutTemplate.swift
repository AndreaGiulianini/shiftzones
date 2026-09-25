import Foundation

/// Starting templates, inspired by FancyZones.
public enum LayoutTemplate: String, CaseIterable, Codable, Identifiable {
    case columns
    case rows
    case grid
    case priorityGrid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .grid: return "Grid"
        case .priorityGrid: return "Priority"
        }
    }

    public func zones(count: Int) -> [Zone] {
        let n = max(1, count)
        switch self {
        case .columns:
            return (0..<n).map { Zone(rect: .edges(minX: fraction($0, n), minY: 0, maxX: fraction($0 + 1, n), maxY: 1)) }
        case .rows:
            return (0..<n).map { Zone(rect: .edges(minX: 0, minY: fraction($0, n), maxX: 1, maxY: fraction($0 + 1, n))) }
        case .grid:
            return grid(n)
        case .priorityGrid:
            return priorityGrid(n)
        }
    }

    /// Columns of stacked zones; extra zones go to the right-hand columns (3 → one large on the left, two on the right).
    private func grid(_ n: Int) -> [Zone] {
        let columns = Int(Double(n).squareRoot().rounded(.up))
        var zones: [Zone] = []
        for column in 0..<columns {
            let rows = n / columns + (column >= columns - n % columns ? 1 : 0)
            zones += stack(rows, minX: fraction(column, columns), maxX: fraction(column + 1, columns))
        }
        return zones
    }

    /// A center zone half the screen wide with quarter-width side columns: meant for ultrawide displays.
    private func priorityGrid(_ n: Int) -> [Zone] {
        switch n {
        case 1:
            return [Zone(rect: .full)]
        case 2:
            return [Zone(rect: .edges(minX: 0, minY: 0, maxX: 2.0 / 3, maxY: 1)),
                    Zone(rect: .edges(minX: 2.0 / 3, minY: 0, maxX: 1, maxY: 1))]
        default:
            let left = (n - 1) / 2
            return stack(left, minX: 0, maxX: 0.25)
                + [Zone(rect: .edges(minX: 0.25, minY: 0, maxX: 0.75, maxY: 1))]
                + stack(n - 1 - left, minX: 0.75, maxX: 1)
        }
    }

    private func stack(_ count: Int, minX: Double, maxX: Double) -> [Zone] {
        (0..<count).map { Zone(rect: .edges(minX: minX, minY: fraction($0, count), maxX: maxX, maxY: fraction($0 + 1, count))) }
    }

    private func fraction(_ index: Int, _ total: Int) -> Double {
        Double(index) / Double(total)
    }
}
