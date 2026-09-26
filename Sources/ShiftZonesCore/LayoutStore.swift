import Foundation

/// Zones of every known display, stored in the text file `~/.config/shiftzones/zones.conf`.
///
/// The file is the source of truth: it is read again after every external change and rewritten
/// when the set of connected displays changes (keeping the zones already defined) or the editor saves.
public final class LayoutStore {
    public let fileURL: URL
    /// Error from the last read; meanwhile the last valid zones stay active.
    public private(set) var error: ZoneFileError?

    private var monitors: [String: MonitorZones] = [:]
    private var fileOrder: [String] = []
    private var listedAsConnected: Set<String> = []
    private var connected: [MonitorDescriptor] = []
    private var hasUpdated = false
    private var lastText: String?

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/shiftzones", isDirectory: true)
            .appendingPathComponent("zones.conf")
    }

    public var backupURL: URL { fileURL.appendingPathExtension("bak") }

    public init(fileURL: URL = LayoutStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func layout(forDisplay displayID: String, aspectRatio: Double) -> ZoneLayout {
        if let monitor = monitors[displayID] { return ZoneLayout(zones: monitor.zones) }
        return Self.defaultLayout(aspectRatio: aspectRatio)
    }

    /// Call at launch and on every display change, with the connected displays from left to right.
    public func update(connected newConnected: [MonitorDescriptor]) {
        // While displays are being reconfigured (sleep, lid closed) macOS can briefly report none at all.
        guard !newConnected.isEmpty else { return }
        let isFirstUpdate = !hasUpdated
        hasUpdated = true
        let setChanged = Set(newConnected.map(\.id)) != Set(connected.map(\.id))
        connected = newConnected
        reloadFile()

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            regenerate()
        } else if error != nil {
            // A file with errors is rewritten only on an actual connect/disconnect, not at
            // launch: it may have been edited while the app wasn't running.
            if setChanged && !isFirstUpdate { regenerate() }
        } else if listedAsConnected != Set(newConnected.map(\.id)) {
            regenerate()
        }
    }

    /// Reads the file again after an external change. Returns true if the zones or the error changed.
    @discardableResult
    public func reload() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            regenerate()
            return true
        }
        return reloadFile()
    }

    /// Save from the visual editor.
    public func setLayout(_ layout: ZoneLayout, forDisplay displayID: String, name: String) {
        var monitor = monitors[displayID] ?? MonitorZones(id: displayID, name: name, resolution: nil, zones: [])
        monitor.zones = layout.zones
        monitors[displayID] = monitor
        regenerate()
    }

    public static func defaultLayout(aspectRatio: Double) -> ZoneLayout {
        switch aspectRatio {
        case ..<1: return ZoneLayout(zones: LayoutTemplate.rows.zones(count: 2))
        case ..<2.1: return ZoneLayout(zones: LayoutTemplate.columns.zones(count: 2))
        default: return ZoneLayout(zones: LayoutTemplate.priorityGrid.zones(count: 3))
        }
    }

    // MARK: - File

    @discardableResult
    private func reloadFile() -> Bool {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text != lastText else { return false }
        lastText = text
        switch ZoneFile.parse(text, connected: connected) {
        case .success(let content):
            monitors = Dictionary(content.monitors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            fileOrder = content.monitors.map(\.id)
            listedAsConnected = content.listedAsConnected
            error = nil
        case .failure(let failure):
            error = failure
        }
        return true
    }

    /// Rewrites the file from scratch: connected displays first (existing or default zones), then disconnected ones.
    private func regenerate() {
        var note: String?
        if error != nil, FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.copyItem(at: fileURL, to: backupURL)) != nil {
                note = "The previous version had errors and was saved as \(backupURL.lastPathComponent)."
            }
        }

        let current = connected.map { monitor in
            MonitorZones(id: monitor.id, name: monitor.name, resolution: monitor.resolution,
                         zones: monitors[monitor.id]?.zones ?? Self.defaultLayout(aspectRatio: monitor.aspectRatio).zones)
        }
        let connectedIDs = Set(connected.map(\.id))
        var seen: Set<String> = []
        let disconnectedIDs = (fileOrder + monitors.keys.sorted())
            .filter { !connectedIDs.contains($0) && seen.insert($0).inserted }

        let text = ZoneFile.render(connected: current,
                                   primaryID: connected.first(where: \.isPrimary)?.id,
                                   disconnected: disconnectedIDs.compactMap { monitors[$0] },
                                   note: note)
        for monitor in current { monitors[monitor.id] = monitor }
        fileOrder = current.map(\.id) + disconnectedIDs
        listedAsConnected = connectedIDs
        error = nil
        write(text)
    }

    private func write(_ text: String) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            lastText = text
        } catch {
            NSLog("ShiftZones: could not write \(fileURL.path): \(error)")
        }
    }
}
