import AppKit
import ShiftZonesCore

/// Transparent windows, one per display, that draw the zones while dragging.
@MainActor
final class OverlayController {
    private let store: LayoutStore
    private var windows: [String: OverlayWindow] = [:]
    private var isVisible = false
    private var screenObserver: NSObjectProtocol?

    init(store: LayoutStore) {
        self.store = store
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.discardWindows() }
        }
    }

    /// - Parameters:
    ///   - layerIndex: layer shown on each display; missing = the first one.
    ///   - highlighted: zones highlighted on the `activeScreenID` display.
    ///   - targetFrame: final frame (AX coordinates), outlined when several zones are combined.
    ///   - windowID: the dragged window; zones are drawn right below it.
    func show(activeScreenID: String, layerIndex: [String: Int], highlighted: Set<UUID>, targetFrame: CGRect?,
              below windowID: CGWindowID?) {
        let screens = NSScreen.screens.filter { Preferences.showOnAllScreens || $0.stableID == activeScreenID }
        let shownIDs = Set(screens.map(\.stableID))
        for (id, window) in windows where !shownIDs.contains(id) {
            window.orderOut(nil)
        }
        for screen in screens {
            let id = screen.stableID
            let window = windows[id] ?? makeWindow(for: screen, id: id)
            let isActive = id == activeScreenID
            let layout = store.layout(for: screen)
            let layer = min(layerIndex[id] ?? 0, max(layout.layers.count - 1, 0))
            window.zoneView.configure(screen: screen,
                                      zones: layout.zones(inLayer: layer),
                                      layerBadge: layerBadge(layer: layer, of: layout.layers.count, isActive: isActive),
                                      spacing: Preferences.spacing,
                                      highlighted: isActive ? highlighted : [],
                                      targetFrame: isActive ? targetFrame : nil)
            if !window.isVisible { present(window, below: windowID) }
        }
        isVisible = true
    }

    /// "Layer 2 of 3", plus the key to switch on the display under the cursor. Nil with a single layer.
    private func layerBadge(layer: Int, of count: Int, isActive: Bool) -> String? {
        guard count > 1 else { return nil }
        let text = "Layer \(layer + 1) of \(count)"
        guard isActive, let key = Preferences.usableLayerModifier else { return text }
        return text + "  ·  press \(key.label) for the next"
    }

    func hide() {
        guard isVisible else { return }
        windows.values.forEach { $0.orderOut(nil) }
        isVisible = false
    }

    private func makeWindow(for screen: NSScreen, id: String) -> OverlayWindow {
        let window = OverlayWindow(screen: screen)
        windows[id] = window
        return window
    }

    private func present(_ window: OverlayWindow, below windowID: CGWindowID?) {
        window.alphaValue = 0
        if let windowID {
            // Above every normal window but below the dragged one, like FancyZones.
            window.level = .normal
            window.order(.below, relativeTo: Int(windowID))
        } else {
            window.level = .floating
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    private func discardWindows() {
        windows.values.forEach { $0.close() }
        windows.removeAll()
        isVisible = false
    }
}

final class OverlayWindow: NSPanel {
    let zoneView = OverlayView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = zoneView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    private struct Item: Equatable {
        let frame: CGRect
        let number: Int
        let highlighted: Bool
    }

    private var items: [Item] = []
    private var targetFrame: CGRect?
    private var layerBadge: String?
    private var visibleArea: CGRect = .zero

    /// Zones are drawn at least this far apart, only to make them easier to tell apart.
    private static let minimumVisualSpacing = 6.0
    private static let cornerRadius: CGFloat = 12

    override var isFlipped: Bool { true }

    func configure(screen: NSScreen, zones: [Zone], layerBadge: String?, spacing: Double, highlighted: Set<UUID>,
                   targetFrame: CGRect?) {
        let origin = screen.axFrame.origin
        let area = screen.axVisibleFrame
        let newItems = zones.enumerated().map { index, zone in
            Item(frame: ZoneGeometry.windowFrame(of: zone.rect, in: area, spacing: max(spacing, Self.minimumVisualSpacing))
                    .offsetBy(dx: -origin.x, dy: -origin.y),
                 number: index + 1,
                 highlighted: highlighted.contains(zone.id))
        }
        let newTarget = highlighted.count > 1 ? targetFrame?.offsetBy(dx: -origin.x, dy: -origin.y) : nil
        let newArea = area.offsetBy(dx: -origin.x, dy: -origin.y)
        guard newItems != items || newTarget != self.targetFrame || layerBadge != self.layerBadge || newArea != visibleArea
        else { return }
        items = newItems
        self.targetFrame = newTarget
        self.layerBadge = layerBadge
        visibleArea = newArea
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for item in items {
            let path = NSBezierPath(roundedRect: item.frame.insetBy(dx: 1.5, dy: 1.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            (item.highlighted ? accent.withAlphaComponent(0.45) : NSColor(white: 0.08, alpha: 0.35)).setFill()
            path.fill()
            path.lineWidth = item.highlighted ? 3 : 1.5
            (item.highlighted ? accent : NSColor(white: 1, alpha: 0.55)).setStroke()
            path.stroke()
            drawNumber(item.number, in: item.frame, emphasized: item.highlighted)
        }
        if let targetFrame {
            let path = NSBezierPath(roundedRect: targetFrame.insetBy(dx: 2, dy: 2), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            path.lineWidth = 4
            accent.setStroke()
            path.stroke()
        }
        if let layerBadge { drawBadge(layerBadge) }
    }

    /// Pill at the top center of the usable area.
    private func drawBadge(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let pill = CGRect(x: visibleArea.midX - size.width / 2 - 16, y: visibleArea.minY + 20,
                          width: size.width + 32, height: size.height + 14)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSColor(white: 0.08, alpha: 0.8).setFill()
        path.fill()
        path.lineWidth = 1
        NSColor(white: 1, alpha: 0.3).setStroke()
        path.stroke()
        string.draw(at: CGPoint(x: pill.minX + 16, y: pill.minY + 7), withAttributes: attributes)
    }

    private func drawNumber(_ number: Int, in rect: CGRect, emphasized: Bool) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(72, max(18, min(rect.width, rect.height) / 4)), weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(emphasized ? 1 : 0.75),
            .shadow: shadow,
        ]
        let text = "\(number)" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}
