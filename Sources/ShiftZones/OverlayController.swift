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
    ///   - highlighted: zones highlighted on the `activeScreenID` display.
    ///   - targetFrame: final frame (AX coordinates), outlined when several zones are combined.
    ///   - windowID: the dragged window; zones are drawn right below it.
    func show(activeScreenID: String, highlighted: Set<UUID>, targetFrame: CGRect?, below windowID: CGWindowID?) {
        let screens = NSScreen.screens.filter { Settings.showOnAllScreens || $0.stableID == activeScreenID }
        let shownIDs = Set(screens.map(\.stableID))
        for (id, window) in windows where !shownIDs.contains(id) {
            window.orderOut(nil)
        }
        for screen in screens {
            let id = screen.stableID
            let window = windows[id] ?? makeWindow(for: screen, id: id)
            let isActive = id == activeScreenID
            window.zoneView.configure(screen: screen,
                                      zones: store.layout(for: screen).zones,
                                      spacing: Settings.spacing,
                                      highlighted: isActive ? highlighted : [],
                                      targetFrame: isActive ? targetFrame : nil)
            if !window.isVisible { present(window, below: windowID) }
        }
        isVisible = true
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

    override var isFlipped: Bool { true }

    func configure(screen: NSScreen, zones: [Zone], spacing: Double, highlighted: Set<UUID>, targetFrame: CGRect?) {
        let origin = screen.axFrame.origin
        let area = screen.axVisibleFrame
        // A minimum gap between zones only makes them easier to tell apart.
        let newItems = zones.enumerated().map { index, zone in
            Item(frame: ZoneGeometry.windowFrame(of: zone.rect, in: area, spacing: max(spacing, 6))
                    .offsetBy(dx: -origin.x, dy: -origin.y),
                 number: index + 1,
                 highlighted: highlighted.contains(zone.id))
        }
        let newTarget = highlighted.count > 1 ? targetFrame?.offsetBy(dx: -origin.x, dy: -origin.y) : nil
        guard newItems != items || newTarget != self.targetFrame else { return }
        items = newItems
        self.targetFrame = newTarget
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for item in items {
            let path = NSBezierPath(roundedRect: item.frame.insetBy(dx: 1.5, dy: 1.5), xRadius: 12, yRadius: 12)
            (item.highlighted ? accent.withAlphaComponent(0.45) : NSColor(white: 0.08, alpha: 0.35)).setFill()
            path.fill()
            path.lineWidth = item.highlighted ? 3 : 1.5
            (item.highlighted ? accent : NSColor(white: 1, alpha: 0.55)).setStroke()
            path.stroke()
            drawNumber(item.number, in: item.frame, emphasized: item.highlighted)
        }
        if let targetFrame {
            let path = NSBezierPath(roundedRect: targetFrame.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
            path.lineWidth = 4
            accent.setStroke()
            path.stroke()
        }
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
