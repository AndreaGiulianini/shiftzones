import Foundation

/// A connected display, as described by the app.
public struct MonitorDescriptor: Equatable, Sendable {
    public var id: String
    public var name: String
    /// Informational only, e.g. "3440 × 1440".
    public var resolution: String
    public var isPrimary: Bool
    public var aspectRatio: Double

    public init(id: String, name: String, resolution: String, isPrimary: Bool = false, aspectRatio: Double = 16.0 / 9) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.isPrimary = isPrimary
        self.aspectRatio = aspectRatio
    }
}

/// A section of the file: one display with its zones.
public struct MonitorZones: Equatable, Sendable {
    public var id: String
    public var name: String
    public var resolution: String?
    public var zones: [Zone]

    public init(id: String, name: String, resolution: String?, zones: [Zone]) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.zones = zones
    }
}

public struct ZoneFileError: Error, Equatable, Sendable {
    public let line: Int
    public let message: String
}

/// The zones text file, meant to be edited by hand:
///
///     [Display name · 3440 × 1440 · primary]
///     id = 37D8832A-2D66-02CA-B9F7-8F30A301B230
///       0    0   25  100
///      25    0   50  100
///
/// Each zone line is `x y width height` as % of the usable area, origin at the top-left.
public enum ZoneFile {
    public struct Content: Equatable, Sendable {
        /// In file order.
        public var monitors: [MonitorZones]
        /// Displays listed before the "disconnected" section.
        public var listedAsConnected: Set<String>
    }

    /// Sections without an `id` line are matched by name against the connected displays.
    public static func parse(_ text: String, connected: [MonitorDescriptor]) -> Result<Content, ZoneFileError> {
        struct Section {
            var id: String?
            var name: String
            var resolution: String?
            var zones: [Zone] = []
            let line: Int
            let listedAsConnected: Bool
        }

        func fail(_ line: Int, _ message: String) -> Result<Content, ZoneFileError> {
            .failure(ZoneFileError(line: line, message: message))
        }

        var sections: [Section] = []
        var inDisconnectedPart = false

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let number = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#") {
                if trimmed.lowercased().contains(disconnectedMarker.lowercased()) { inDisconnectedPart = true }
                continue
            }

            if trimmed.hasPrefix("[") {
                guard trimmed.hasSuffix("]") else { return fail(number, "missing ']' at the end of the display header") }
                let parts = trimmed.dropFirst().dropLast()
                    .components(separatedBy: "·")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let name = parts.first, !name.isEmpty else { return fail(number, "missing the display name between the square brackets") }
                sections.append(Section(id: nil, name: name, resolution: parts.dropFirst().first { $0.contains("×") },
                                        line: number, listedAsConnected: !inDisconnectedPart))
                continue
            }

            let content = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            guard !sections.isEmpty else {
                return fail(number, "this line must come after a display header, for example [Display name]")
            }

            if let equals = content.firstIndex(of: "=") {
                let key = content[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
                let value = content[content.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                guard key == "id" else { return fail(number, "unknown setting '\(key)': the only one allowed is 'id'") }
                guard !value.isEmpty else { return fail(number, "the display id is empty") }
                guard sections[sections.count - 1].id == nil else { return fail(number, "this display already has an id") }
                sections[sections.count - 1].id = value
                continue
            }

            switch parseZone(content) {
            case .success(let zone): sections[sections.count - 1].zones.append(zone)
            case .failure(let message): return fail(number, message.text)
            }
        }

        var monitors: [MonitorZones] = []
        var connectedIDs: Set<String> = []
        var firstLine: [String: Int] = [:]
        for section in sections {
            let id: String
            if let explicit = section.id {
                id = explicit
            } else {
                let matches = connected.filter { $0.name == section.name }
                guard matches.count == 1 else {
                    return fail(section.line, "missing the 'id = …' line for display '\(section.name)'")
                }
                id = matches[0].id
            }
            if let previous = firstLine[id] {
                return fail(section.line, "this display is already described at line \(previous)")
            }
            firstLine[id] = section.line
            monitors.append(MonitorZones(id: id, name: section.name, resolution: section.resolution, zones: section.zones))
            if section.listedAsConnected { connectedIDs.insert(id) }
        }
        return .success(Content(monitors: monitors, listedAsConnected: connectedIDs))
    }

    public static func render(connected: [MonitorZones], primaryID: String?, disconnected: [MonitorZones],
                              note: String? = nil) -> String {
        var lines = header
        if let note { lines += ["", "# ⚠︎ \(note)"] }
        for monitor in connected {
            lines += [""] + section(monitor, isPrimary: monitor.id == primaryID)
        }
        if !disconnected.isEmpty {
            lines += ["", "",
                      "# ─── \(disconnectedMarker) " + String(repeating: "─", count: 50),
                      "# Their zones come back when you reconnect them. Delete a section to forget a display."]
            for monitor in disconnected {
                lines += [""] + section(monitor, isPrimary: false)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Details

    static let disconnectedMarker = "Disconnected displays"

    private static let header = [
        "# ShiftZones — display zones",
        "#",
        "# Each display has a [name · resolution] section with its id and one line per zone:",
        "#",
        "#     x  y  width  height",
        "#",
        "# as % of the usable screen area (menu bar and Dock excluded), with the origin at the top-left.",
        "# Decimals (33.3 or 33,3) and a % sign (25%) are allowed. Anything after # is a comment.",
        "# The number shown on each zone is the position of its line. A display with no lines has no zones.",
        "#",
        "# Example: three columns 30% | 40% | 30%, with the third one split in half vertically",
        "#" + columns(["0", "0", "30", "100"]),
        "#" + columns(["30", "0", "40", "100"]),
        "#" + columns(["70", "0", "30", "50"]),
        "#" + columns(["70", "50", "30", "50"]),
        "#",
        "# Changes apply as soon as you save. When a display is connected or disconnected the file is",
        "# rewritten: your zones are kept, hand-written comments are not.",
    ]

    private static func section(_ monitor: MonitorZones, isPrimary: Bool) -> [String] {
        let title = ([monitor.name] + [monitor.resolution].compactMap { $0 } + (isPrimary ? ["primary"] : []))
            .joined(separator: " · ")
        var lines = ["[\(title)]", "id = \(monitor.id)"]
        guard !monitor.zones.isEmpty else {
            return lines + ["# no zones: zones are turned off on this display"]
        }
        lines.append("#" + String(columns(["x", "y", "width", "height"]).dropFirst()))
        for zone in monitor.zones {
            // Round the edges, not the sizes, so that adjacent zones stay exactly flush.
            let minX = percent(zone.rect.minX), maxX = percent(zone.rect.maxX)
            let minY = percent(zone.rect.minY), maxY = percent(zone.rect.maxY)
            lines.append(columns([minX, minY, maxX - minX, maxY - minY].map(format)))
        }
        return lines
    }

    private static func columns(_ values: [String]) -> String {
        values.map { String(repeating: " ", count: max(1, 7 - $0.count)) + $0 }.joined()
    }

    /// Fraction to percentage with two decimals.
    private static func percent(_ fraction: Double) -> Double {
        (fraction * 10_000).rounded() / 100
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    private struct Message: Error { let text: String }

    private static func parseZone(_ content: String) -> Result<Zone, Message> {
        let tokens = content.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { token -> String? in
            var text = String(token)
            while let last = text.last, last == "," || last == ";" || last == "%" { text.removeLast() }
            return text.isEmpty ? nil : text.replacingOccurrences(of: ",", with: ".")
        }
        guard tokens.count == 4 else {
            return .failure(Message(text: "a zone is made of 4 numbers (x y width height), found \(tokens.count)"))
        }
        var values: [Double] = []
        for token in tokens {
            guard let value = Double(token), value.isFinite else { return .failure(Message(text: "'\(token)' is not a number")) }
            values.append(value)
        }
        let (x, y, width, height) = (values[0], values[1], values[2], values[3])
        let tolerance = 0.01
        guard x >= 0, y >= 0 else { return .failure(Message(text: "x and y can't be negative")) }
        guard width > 0, height > 0 else { return .failure(Message(text: "width and height must be greater than 0")) }
        guard x + width <= 100 + tolerance else {
            return .failure(Message(text: "the zone goes past the right edge: x + width is \(format(x + width))%, at most 100%"))
        }
        guard y + height <= 100 + tolerance else {
            return .failure(Message(text: "the zone goes past the bottom edge: y + height is \(format(y + height))%, at most 100%"))
        }
        return .success(Zone(rect: .edges(minX: x / 100, minY: y / 100,
                                          maxX: min(x + width, 100) / 100, maxY: min(y + height, 100) / 100)))
    }
}
