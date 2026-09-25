import AppKit
import ShiftZonesCore

@MainActor
protocol ZoneCanvasDelegate: AnyObject {
    func canvasRequestsSave()
    func canvasRequestsCancel()
    /// A manual edit (not applying a template).
    func canvasDidEditManually()
}

/// The editor canvas: zones are moved, resized, split and deleted with the mouse.
final class ZoneCanvasView: NSView {
    weak var delegate: ZoneCanvasDelegate?

    private(set) var zones: [Zone] { didSet { needsDisplay = true } }
    private var selectedID: UUID? { didSet { needsDisplay = true } }
    /// Usable area of the display, in view coordinates.
    private let area: CGRect
    private var history: [[Zone]] = []
    private var interaction: Interaction?

    private struct Interaction {
        let zoneID: UUID
        /// Empty = move.
        let edges: ResizeEdges
        let startZones: [Zone]
        let startPoint: CGPoint
    }

    private static let edgeTolerance: CGFloat = 8
    private static let magnetDistance: CGFloat = 12
    private static let minimumZoneSize: CGFloat = 80

    init(area: CGRect, zones: [Zone]) {
        self.area = area
        self.zones = zones
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Editing

    func replaceZones(_ newZones: [Zone]) {
        pushHistory()
        zones = newZones
        selectedID = nil
    }

    func addZone(centeredAt point: CGPoint? = nil) {
        let width = 1.0 / 3, height = 0.5
        let center = point.map { CGPoint(x: ($0.x - area.minX) / area.width, y: ($0.y - area.minY) / area.height) }
            ?? CGPoint(x: 0.5, y: 0.5)
        let rect = ZoneRect(x: min(max(Double(center.x) - width / 2, 0), 1 - width),
                            y: min(max(Double(center.y) - height / 2, 0), 1 - height),
                            width: width, height: height)
        let zone = Zone(rect: rect)
        pushHistory()
        zones.append(zone)
        selectedID = zone.id
        delegate?.canvasDidEditManually()
    }

    @objc private func deleteSelected() {
        guard let selectedID else { NSSound.beep(); return }
        pushHistory()
        zones.removeAll { $0.id == selectedID }
        self.selectedID = nil
        delegate?.canvasDidEditManually()
    }

    @objc private func duplicateSelected() {
        guard let zone = selectedZone else { return }
        var rect = zone.rect
        rect.x = min(rect.x + 0.03, 1 - rect.width)
        rect.y = min(rect.y + 0.03, 1 - rect.height)
        let copy = Zone(rect: rect)
        pushHistory()
        zones.append(copy)
        selectedID = copy.id
        delegate?.canvasDidEditManually()
    }

    @objc private func splitIntoColumns() { splitSelected(.columns) }
    @objc private func splitIntoRows() { splitSelected(.rows) }

    private func splitSelected(_ orientation: SplitOrientation) {
        guard let index = zones.firstIndex(where: { $0.id == selectedID }) else { return }
        pushHistory()
        zones.replaceSubrange(index...index, with: ZoneEditing.split(zones[index], orientation))
        delegate?.canvasDidEditManually()
    }

    private func pushHistory() {
        history.append(zones)
        if history.count > 100 { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { NSSound.beep(); return }
        zones = previous
        selectedID = nil
        delegate?.canvasDidEditManually()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTarget(at: point) else {
            selectedID = nil
            if event.clickCount == 2, area.contains(point) { addZone(centeredAt: point) }
            return
        }
        selectedID = hit.zone.id
        interaction = Interaction(zoneID: hit.zone.id, edges: hit.edges, startZones: zones, startPoint: point)
        updateCursor(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let interaction else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = Double((point.x - interaction.startPoint.x) / area.width)
        let dy = Double((point.y - interaction.startPoint.y) / area.height)
        // ⌘ turns off snapping, ⌥ resizes only the dragged zone.
        let magnet = !event.modifierFlags.contains(.command)
        let threshold = magnet
            ? (x: Double(Self.magnetDistance / area.width), y: Double(Self.magnetDistance / area.height))
            : (x: 0.0, y: 0.0)

        if interaction.edges.isEmpty {
            zones = ZoneEditing.move(interaction.zoneID, in: interaction.startZones, dx: dx, dy: dy, threshold: threshold)
        } else {
            zones = ZoneEditing.resize(interaction.zoneID, in: interaction.startZones, edges: interaction.edges,
                                       dx: dx, dy: dy, linked: !event.modifierFlags.contains(.option),
                                       threshold: threshold,
                                       minSize: (width: Double(Self.minimumZoneSize / area.width),
                                                 height: Double(Self.minimumZoneSize / area.height)))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let interaction, interaction.startZones != zones {
            history.append(interaction.startZones)
            delegate?.canvasDidEditManually()
        }
        interaction = nil
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = hitTarget(at: convert(event.locationInWindow, from: nil)) else { return nil }
        selectedID = hit.zone.id
        let menu = NSMenu()
        menu.addItem(menuItem("Split into Columns", #selector(splitIntoColumns)))
        menu.addItem(menuItem("Split into Rows", #selector(splitIntoRows)))
        menu.addItem(menuItem("Duplicate", #selector(duplicateSelected)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Delete", #selector(deleteSelected)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            undo()
            return
        }
        switch event.keyCode {
        case 51, 117: deleteSelected()                      // ⌫, forward delete
        case 53: delegate?.canvasRequestsCancel()           // esc
        case 36, 76: delegate?.canvasRequestsSave()         // return
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Hit testing and cursor

    private var selectedZone: Zone? { zones.first { $0.id == selectedID } }

    private func frame(for zone: Zone) -> CGRect {
        ZoneGeometry.hitFrame(of: zone.rect, in: area)
    }

    /// Zone (and edges) under the point: the selected one first, then the others from the top.
    private func hitTarget(at point: CGPoint) -> (zone: Zone, edges: ResizeEdges)? {
        var candidates = Array(zones.reversed())
        if let selected = selectedZone {
            candidates.removeAll { $0.id == selected.id }
            candidates.insert(selected, at: 0)
        }
        for zone in candidates {
            let frame = frame(for: zone)
            let edges = edges(at: point, in: frame)
            if !edges.isEmpty || frame.contains(point) { return (zone, edges) }
        }
        return nil
    }

    private func edges(at point: CGPoint, in frame: CGRect) -> ResizeEdges {
        let t = Self.edgeTolerance
        guard frame.insetBy(dx: -t, dy: -t).contains(point) else { return [] }
        var edges: ResizeEdges = []
        if abs(point.x - frame.minX) <= t { edges.insert(.left) } else if abs(point.x - frame.maxX) <= t { edges.insert(.right) }
        if abs(point.y - frame.minY) <= t { edges.insert(.top) } else if abs(point.y - frame.maxY) <= t { edges.insert(.bottom) }
        return edges
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at point: CGPoint) {
        guard let hit = hitTarget(at: point) else { NSCursor.arrow.set(); return }
        switch hit.edges {
        case []: (interaction == nil ? NSCursor.openHand : NSCursor.closedHand).set()
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        default: NSCursor.crosshair.set()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.55).setFill()
        bounds.fill()
        NSColor(white: 1, alpha: 0.05).setFill()
        area.fill()
        let border = NSBezierPath(rect: area.insetBy(dx: 0.5, dy: 0.5))
        border.setLineDash([6, 4], count: 2, phase: 0)
        NSColor(white: 1, alpha: 0.35).setStroke()
        border.stroke()

        for (index, zone) in zones.enumerated() where zone.id != selectedID {
            draw(zone, number: index + 1, selected: false)
        }
        if let index = zones.firstIndex(where: { $0.id == selectedID }) {
            draw(zones[index], number: index + 1, selected: true)
        }
        if zones.isEmpty {
            drawCentered("No zones on this display.\nPick a template or double-click to add one.",
                         in: area, font: .systemFont(ofSize: 20, weight: .medium), color: NSColor(white: 1, alpha: 0.8))
        }
    }

    private func draw(_ zone: Zone, number: Int, selected: Bool) {
        let accent = NSColor.controlAccentColor
        let rect = frame(for: zone).insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        accent.withAlphaComponent(selected ? 0.5 : 0.25).setFill()
        path.fill()
        path.lineWidth = selected ? 3 : 1.5
        (selected ? NSColor.white : accent.withAlphaComponent(0.9)).setStroke()
        path.stroke()

        let windowSize = ZoneGeometry.windowFrame(of: zone.rect, in: area, spacing: Settings.spacing).size
        let numberFont = NSFont.systemFont(ofSize: min(64, max(16, min(rect.width, rect.height) / 5)), weight: .bold)
        drawCentered("\(number)", in: rect.offsetBy(dx: 0, dy: -12), font: numberFont, color: .white)
        drawCentered("\(Int(windowSize.width)) × \(Int(windowSize.height))",
                     in: rect.offsetBy(dx: 0, dy: numberFont.pointSize / 2 + 8),
                     font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: NSColor(white: 1, alpha: 0.75))

        if selected { drawHandles(around: frame(for: zone)) }
    }

    private func drawHandles(around rect: CGRect) {
        let xs = [rect.minX, rect.midX, rect.maxX], ys = [rect.minY, rect.midY, rect.maxY]
        for x in xs {
            for y in ys where !(x == rect.midX && y == rect.midY) {
                let handle = NSBezierPath(roundedRect: CGRect(x: x - 5, y: y - 5, width: 10, height: 10), xRadius: 2, yRadius: 2)
                NSColor.white.setFill()
                handle.fill()
                handle.lineWidth = 1.5
                NSColor.controlAccentColor.setStroke()
                handle.stroke()
            }
        }
    }

    private func drawCentered(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 4
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                         .paragraphStyle: paragraph, .shadow: shadow]
        let string = text as NSString
        let size = string.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin], attributes: attributes).size
        string.draw(with: CGRect(x: rect.minX, y: rect.midY - size.height / 2, width: rect.width, height: size.height),
                    options: [.usesLineFragmentOrigin], attributes: attributes)
    }
}
