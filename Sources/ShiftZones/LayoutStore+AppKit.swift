import AppKit
import ShiftZonesCore

extension LayoutStore {
    func layout(for screen: NSScreen) -> ZoneLayout {
        layout(forDisplay: screen.stableID, aspectRatio: screen.aspectRatio)
    }

    /// Opens the zones file in the default text editor.
    func openInEditor() {
        let workspace = NSWorkspace.shared
        if workspace.urlForApplication(toOpen: fileURL) != nil {
            workspace.open(fileURL)
        } else if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            // No app associated with .conf files: fall back to TextEdit.
            workspace.open([fileURL], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
