import AppKit
import ShiftZonesCore

/// Detects when a window is being dragged and, while the activation key is held,
/// shows the zones and moves the window into the zone under the cursor on release.
@MainActor
final class DragController {
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
    private var detector = WindowDragDetector<AXWindow>()
    private var target: SnapTarget?
    private var spanAnchor: (screenID: String, zone: Zone)?
    private var snapped: [AXWindow: SnapRecord] = [:]

    /// Some apps finish their own drag after mouseUp, so the frame is applied again after this delay.
    private static let reapplyDelay: TimeInterval = 0.1
    /// Past this many remembered windows, the ones that have been closed are forgotten.
    private static let snapRecordLimit = 64

    init(store: LayoutStore, overlay: OverlayController) {
        self.store = store
        self.overlay = overlay
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        guard Preferences.enabled else { return }
        switch event.type {
        case .leftMouseDown:
            reset()
            detector.mouseDown()
        case .leftMouseDragged:
            mouseDragged()
        case .leftMouseUp:
            mouseUp()
        case .flagsChanged:
            if detector.draggedWindow != nil { refresh() }
        default:
            break
        }
    }

    private func mouseDragged() {
        guard detector.draggedWindow == nil else {
            refresh()
            return
        }
        // The live frame comes from the window server: the Accessibility one lags behind during a drag.
        let started = detector.mouseDragged(windowUnderCursor: { AXWindow.under(ScreenGeometry.mouseLocation()) },
                                            frame: { $0.liveFrame })
        if let started { beginDrag(started.window, frame: started.frame) }
    }

    private func beginDrag(_ window: AXWindow, frame: CGRect) {
        if Preferences.restoreSizeOnUnsnap, let record = snapped.removeValue(forKey: window),
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
        guard let window = detector.draggedWindow, let target else { return }
        let originalSize = snapped[window]?.originalSize ?? window.frame?.size
        window.setFrame(target.frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reapplyDelay) {
            if let frame = window.frame, !frame.isClose(to: target.frame) {
                window.setFrame(target.frame)
            }
        }
        if snapped.count >= Self.snapRecordLimit { snapped = snapped.filter { $0.key.exists } }
        if let originalSize {
            snapped[window] = SnapRecord(originalSize: originalSize, snappedFrame: target.frame)
        }
    }

    // MARK: - Zones

    private var activationHeld: Bool {
        let activation = Preferences.activationModifier
        return activation == .off || activation.isHeld(in: NSEvent.modifierFlags)
    }

    private var spanHeld: Bool {
        let span = Preferences.spanModifier
        return span != Preferences.activationModifier && span.isHeld(in: NSEvent.modifierFlags)
    }

    /// Updates the highlighted zone and the overlay from the cursor and the held keys.
    private func refresh() {
        guard let window = detector.draggedWindow else { return }
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
                                frame: ZoneGeometry.windowFrame(of: bounds, in: area, spacing: Preferences.spacing))
        } else {
            target = nil
        }

        overlay.show(activeScreenID: screenID,
                     highlighted: target?.zoneIDs ?? [],
                     targetFrame: target?.frame,
                     below: window.windowID)
    }

    private func reset() {
        detector.reset()
        target = nil
        spanAnchor = nil
        overlay.hide()
    }
}
