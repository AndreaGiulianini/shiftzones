import AppKit
import ShiftZonesCore

/// Detects when a window is being dragged and, while the activation key is held,
/// shows the zones and moves the window into the zone under the cursor on release.
@MainActor
final class DragController {
    private enum Phase {
        case idle
        /// Left button down, no movement yet.
        case pressed
        /// The mouse is moving: checking whether it is moving the window under the cursor.
        case candidate(window: AXWindow, initialFrame: CGRect)
        case dragging(AXWindow)
        /// A drag that doesn't move a window (text selection, resizing…).
        case ignored
    }

    private struct SnapTarget {
        let screenID: String
        let zoneIDs: Set<UUID>
        let frame: CGRect
    }

    /// Size before snapping, restored when the window is dragged out of the zone.
    private struct SnapRecord {
        let originalSize: CGSize
        let snappedFrame: CGRect
    }

    private let store: LayoutStore
    private let overlay: OverlayController
    private var monitor: Any?
    private var phase: Phase = .idle
    private var target: SnapTarget?
    private var spanAnchor: (screenID: String, zone: Zone)?
    private var snapped: [AXWindow: SnapRecord] = [:]

    init(store: LayoutStore, overlay: OverlayController) {
        self.store = store
        self.overlay = overlay
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        guard Settings.enabled else { return }
        switch event.type {
        case .leftMouseDown:
            reset()
            phase = .pressed
        case .leftMouseDragged:
            mouseDragged()
        case .leftMouseUp:
            mouseUp()
        case .flagsChanged:
            if case .dragging = phase { refresh() }
        default:
            break
        }
    }

    private func mouseDragged() {
        switch phase {
        case .pressed:
            // Look up the window only on the first movement: no AX calls on plain clicks.
            let point = ScreenGeometry.mouseLocation()
            if let window = AXWindow.under(point), let frame = window.liveFrame {
                phase = .candidate(window: window, initialFrame: frame)
            } else {
                phase = .ignored
            }
        case let .candidate(window, initialFrame):
            // Keep checking until the button is released: some apps start moving the window late.
            guard let frame = window.liveFrame else { phase = .ignored; return }
            if !frame.size.isClose(to: initialFrame.size, tolerance: 1) {
                phase = .ignored
            } else if frame.origin != initialFrame.origin {
                beginDrag(window, frame: frame)
            }
        case .dragging:
            refresh()
        case .idle, .ignored:
            break
        }
    }

    private func beginDrag(_ window: AXWindow, frame: CGRect) {
        phase = .dragging(window)
        if Settings.restoreSizeOnUnsnap, let record = snapped.removeValue(forKey: window),
           frame.size.isClose(to: record.snappedFrame.size) {
            restore(window, from: frame, to: record.originalSize)
        }
        refresh()
    }

    /// Restores the original size, keeping the cursor at the same relative spot.
    private func restore(_ window: AXWindow, from frame: CGRect, to size: CGSize) {
        let cursor = ScreenGeometry.mouseLocation()
        let ratio = frame.width > 0 ? (cursor.x - frame.minX) / frame.width : 0.5
        window.setSize(size)
        window.setPosition(CGPoint(x: cursor.x - size.width * ratio, y: frame.minY))
    }

    private func mouseUp() {
        defer { reset() }
        guard case let .dragging(window) = phase, let target else { return }
        let originalSize = snapped[window]?.originalSize ?? window.frame?.size
        window.setFrame(target.frame)
        // Some apps finish their own drag after mouseUp: apply the frame again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let frame = window.frame, !frame.isClose(to: target.frame) {
                window.setFrame(target.frame)
            }
        }
        if snapped.count > 256 { snapped.removeAll() }
        if let originalSize {
            snapped[window] = SnapRecord(originalSize: originalSize, snappedFrame: target.frame)
        }
    }

    // MARK: - Zones

    private var activationHeld: Bool {
        let activation = Settings.activationModifier
        return activation == .none || activation.isHeld(in: NSEvent.modifierFlags)
    }

    private var spanHeld: Bool {
        let span = Settings.spanModifier
        return span != Settings.activationModifier && span.isHeld(in: NSEvent.modifierFlags)
    }

    /// Updates the highlighted zone and the overlay from the cursor and the held keys.
    private func refresh() {
        guard case let .dragging(window) = phase else { return }
        guard activationHeld else {
            target = nil
            spanAnchor = nil
            overlay.hide()
            return
        }

        let point = ScreenGeometry.mouseLocation()
        guard let screen = ScreenGeometry.screen(containing: point) else { return }
        let screenID = screen.stableID
        let zones = store.layout(for: screen).zones
        let area = screen.axVisibleFrame

        var selection: [Zone] = []
        if let zone = ZoneGeometry.zone(at: point, in: zones, area: area) {
            if spanHeld {
                if spanAnchor?.screenID != screenID { spanAnchor = (screenID, zone) }
                selection = ZoneGeometry.span(from: spanAnchor?.zone ?? zone, to: zone, in: zones)
            } else {
                spanAnchor = nil
                selection = [zone]
            }
        }

        if let bounds = ZoneGeometry.boundingRect(of: selection) {
            target = SnapTarget(screenID: screenID,
                                zoneIDs: Set(selection.map(\.id)),
                                frame: ZoneGeometry.windowFrame(of: bounds, in: area, spacing: Settings.spacing))
        } else {
            target = nil
        }

        overlay.show(activeScreenID: screenID,
                     highlighted: target?.zoneIDs ?? [],
                     targetFrame: target?.frame,
                     below: window.windowID)
    }

    private func reset() {
        phase = .idle
        target = nil
        spanAnchor = nil
        overlay.hide()
    }
}
