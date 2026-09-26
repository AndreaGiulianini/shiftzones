import AppKit
import ShiftZonesCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = LayoutStore()
    private lazy var overlay = OverlayController(store: store)
    private lazy var drag = DragController(store: store, overlay: overlay)
    private lazy var settingsModel = SettingsModel(store: store) { [weak self] screenID in
        self?.editZones(screenID: screenID)
    }
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var editor: ZoneEditor?
    private var appBeforeEditor: NSRunningApplication?
    private var trustTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var zonesWatcher: DirectoryWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        store.update(connected: ScreenGeometry.connectedMonitors())
        setupStatusItem()

        // Manual edits to the zones file take effect as soon as they are saved.
        zonesWatcher = DirectoryWatcher(directory: store.fileURL.deletingLastPathComponent()) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.store.reload() else { return }
                self.zonesFileChanged()
            }
        }

        // Display connected or disconnected: the file is rewritten with the updated list.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.editor?.cancel()
                self.store.update(connected: ScreenGeometry.connectedMonitors())
                self.zonesFileChanged()
            }
        }

        if Accessibility.isTrusted {
            drag.start()
        } else {
            Accessibility.requestTrust()
            waitForTrust()
            showSettings()
        }

        // Handy during development: --settings, --edit-screen <index>
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--settings") { showSettings() }
        if let flag = arguments.firstIndex(of: "--edit-screen"), flag + 1 < arguments.count,
           let index = Int(arguments[flag + 1]), NSScreen.screens.indices.contains(index) {
            editZones(screenID: NSScreen.screens[index].stableID)
        }
    }

    /// The permission can be granted at any moment: keep checking until it is.
    private func waitForTrust() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, Accessibility.isTrusted else { return }
                timer.invalidate()
                self.drag.start()
                self.settingsModel.refresh()
                self.updateStatusIcon()
            }
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "ShiftZones")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let symbol = store.error == nil ? "rectangle.split.3x1" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ShiftZones")
        statusItem.button?.appearsDisabled = !Preferences.enabled || !Accessibility.isTrusted
    }

    private func zonesFileChanged() {
        settingsModel.refresh()
        updateStatusIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !Accessibility.isTrusted {
            menu.addItem(item("Grant Accessibility Permission…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        if let error = store.error {
            menu.addItem(item("Error in the zones file at line \(error.line)", #selector(openZonesFile)))
            let detail = NSMenuItem(title: error.message, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            detail.indentationLevel = 1
            menu.addItem(detail)
            menu.addItem(.separator())
        }

        let toggle = item("Zones Enabled", #selector(toggleEnabled))
        toggle.state = Preferences.enabled ? .on : .off
        menu.addItem(toggle)

        let activation = Preferences.activationModifier
        let hint = NSMenuItem(title: activation == .off
                              ? "Drag a window onto a zone"
                              : "Drag a window while holding \(activation.label)",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let editHeader = NSMenuItem(title: "Edit Zones", action: nil, keyEquivalent: "")
        editHeader.isEnabled = false
        menu.addItem(editHeader)
        for screen in ScreenGeometry.screensLeftToRight {
            let isPrimary = screen == NSScreen.screens.first
            let entry = item(screen.localizedName + (isPrimary ? " (primary)" : ""), #selector(editZonesFromMenu(_:)))
            entry.representedObject = screen.stableID
            entry.indentationLevel = 1
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        menu.addItem(item("Open Zones File", #selector(openZonesFile)))
        let reveal = item("Show Zones File in Finder", #selector(revealZonesFile))
        reveal.isAlternate = true
        reveal.keyEquivalentModifierMask = .option
        menu.addItem(reveal)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit ShiftZones", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        Preferences.enabled.toggle()
        updateStatusIcon()
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.openSystemSettings()
    }

    @objc private func openZonesFile() {
        store.openInEditor()
    }

    @objc private func revealZonesFile() {
        store.revealInFinder()
    }

    @objc private func editZonesFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        editZones(screenID: id)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Editor and settings

    private func editZones(screenID: String) {
        guard let screen = ScreenGeometry.screen(withID: screenID) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost != .current { appBeforeEditor = frontmost }
        let previous = editor
        let editor = ZoneEditor(screen: screen, store: store) { [weak self] closed, _ in
            self?.editorDidClose(closed)
        }
        self.editor = editor
        previous?.cancel()
        editor.show()
    }

    private func editorDidClose(_ closed: ZoneEditor) {
        // An editor replaced by another one must not touch the new one's state.
        guard closed === editor else { return }
        editor = nil
        settingsModel.refresh()
        // No NSApp.hide: it would also hide the zone windows shown during later drags.
        if settingsWindow?.isVisible != true, let app = appBeforeEditor, !app.isTerminated {
            if #available(macOS 14.0, *) { app.activate() } else { app.activate(options: []) }
        }
        appBeforeEditor = nil
    }

    @objc private func showSettings() {
        settingsModel.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: settingsModel)))
            window.title = "ShiftZones"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 580, height: 860))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.bringToFront()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
