import AppKit
import ShiftZonesCore

/// Full-screen zone editor for one display, with a floating toolbar.
@MainActor
final class ZoneEditor: NSObject {
    let screenID: String
    private let screen: NSScreen
    private let store: LayoutStore
    private let onClose: (_ editor: ZoneEditor, _ saved: Bool) -> Void
    private let window: EditorWindow
    private let canvas: ZoneCanvasView
    private var toolbar: NSPanel!
    private var templates: NSSegmentedControl!
    private let stepper = NSStepper()
    private let countLabel = NSTextField(labelWithString: "")

    init(screen: NSScreen, store: LayoutStore, onClose: @escaping (_ editor: ZoneEditor, _ saved: Bool) -> Void) {
        self.screen = screen
        self.screenID = screen.stableID
        self.store = store
        self.onClose = onClose
        let origin = screen.axFrame.origin
        canvas = ZoneCanvasView(area: screen.axVisibleFrame.offsetBy(dx: -origin.x, dy: -origin.y),
                                zones: store.layout(for: screen).zones)
        window = EditorWindow(screen: screen)
        super.init()
        canvas.delegate = self
        window.contentView = canvas
        toolbar = makeToolbar()
    }

    func show() {
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        window.addChildWindow(toolbar, ordered: .above)
        let visible = screen.visibleFrame, size = toolbar.frame.size
        toolbar.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24))
        toolbar.orderFront(nil)
    }

    func cancel() {
        finish(saved: false)
    }

    private func finish(saved: Bool) {
        guard window.isVisible else { return }
        if saved {
            store.setLayout(ZoneLayout(zones: canvas.zones), forDisplay: screenID, name: screen.localizedName)
        }
        window.removeChildWindow(toolbar)
        toolbar.orderOut(nil)
        window.orderOut(nil)
        onClose(self, saved)
    }

    // MARK: - Toolbar

    @objc private func applyTemplate(_ sender: NSSegmentedControl) {
        guard LayoutTemplate.allCases.indices.contains(sender.selectedSegment) else { return }
        canvas.replaceZones(LayoutTemplate.allCases[sender.selectedSegment].zones(count: stepper.integerValue))
    }

    @objc private func countChanged(_ sender: NSStepper) {
        countLabel.stringValue = "\(sender.integerValue)"
        // The zone count belongs to the selected template: apply it again right away.
        if LayoutTemplate.allCases.indices.contains(templates.selectedSegment) {
            applyTemplate(templates)
        }
    }

    @objc private func addZone() { canvas.addZone() }
    @objc private func removeAll() { canvas.replaceZones([]) }
    @objc private func savePressed() { finish(saved: true) }
    @objc private func cancelPressed() { finish(saved: false) }

    private func makeToolbar() -> NSPanel {
        let title = NSTextField(labelWithString: screen.localizedName)
        title.font = .boldSystemFont(ofSize: 13)

        templates = NSSegmentedControl(labels: LayoutTemplate.allCases.map(\.title), trackingMode: .selectOne,
                                       target: self, action: #selector(applyTemplate(_:)))
        templates.selectedSegment = -1

        let initialCount = canvas.zones.isEmpty ? 3 : min(canvas.zones.count, 12)
        stepper.minValue = 1
        stepper.maxValue = 12
        stepper.integerValue = initialCount
        stepper.target = self
        stepper.action = #selector(countChanged(_:))
        countLabel.stringValue = "\(initialCount)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        countLabel.alignment = .right
        countLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let save = NSButton(title: "Save", target: self, action: #selector(savePressed))
        save.bezelColor = .controlAccentColor
        save.keyEquivalent = "\r"

        let row = NSStackView(views: [
            title, separator(),
            templates, NSTextField(labelWithString: "Zones:"), countLabel, stepper, separator(),
            NSButton(title: "Add Zone", target: self, action: #selector(addZone)),
            NSButton(title: "Remove All", target: self, action: #selector(removeAll)), separator(),
            NSButton(title: "Cancel", target: self, action: #selector(cancelPressed)), save,
        ])
        row.spacing = 10
        row.alignment = .centerY
        row.setClippingResistancePriority(.required, for: .horizontal)

        let hints = [
            "Drag to move · drag the edges to resize (⌥ this zone only, ⌘ no snapping)",
            "Double-click empty space to add · right-click to split · ⌫ delete · ⌘Z undo · ↩ save · esc exit",
        ].map { text -> NSTextField in
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            return label
        }

        let stack = NSStackView(views: [row] + hints)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: row)
        stack.setClippingResistancePriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = .roundedMask(radius: 14)
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
        ])

        let panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = window.level
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = background
        panel.setContentSize(background.fittingSize)
        return panel
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }
}

extension ZoneEditor: ZoneCanvasDelegate {
    func canvasRequestsSave() { finish(saved: true) }
    func canvasRequestsCancel() { finish(saved: false) }
    func canvasDidEditManually() { templates.selectedSegment = -1 }
}

/// Covers the whole display (menu bar and Dock included) while staying below context menus.
final class EditorWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The toolbar never becomes key: the keyboard always goes to the zone canvas.
final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
func activateApp() {
    if #available(macOS 14.0, *) {
        NSApp.activate()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension NSImage {
    /// Resizable rounded-corner mask for NSVisualEffectView.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
