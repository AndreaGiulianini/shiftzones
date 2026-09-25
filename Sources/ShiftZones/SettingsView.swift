import ShiftZonesCore
import ServiceManagement
import SwiftUI

struct ScreenInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let details: String
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var screens: [ScreenInfo] = []
    @Published private(set) var isTrusted = Accessibility.isTrusted
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var fileError: String?

    private let store: LayoutStore
    let editScreen: (String) -> Void

    var filePath: String { (store.fileURL.path as NSString).abbreviatingWithTildeInPath }
    func openFile() { ZonesFile.open(store.fileURL) }
    func revealFile() { ZonesFile.reveal(store.fileURL) }

    init(store: LayoutStore, editScreen: @escaping (String) -> Void) {
        self.store = store
        self.editScreen = editScreen
        refresh()
    }

    func refresh() {
        isTrusted = Accessibility.isTrusted
        launchAtLogin = SMAppService.mainApp.status == .enabled
        fileError = store.error.map { "Line \($0.line): \($0.message)" }
        screens = ScreenGeometry.screensLeftToRight.map { screen in
            let count = store.layout(for: screen).zones.count
            var parts = ["\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt",
                         count == 1 ? "1 zone" : "\(count) zones"]
            if screen == NSScreen.screens.first { parts.append("primary") }
            return ScreenInfo(id: screen.stableID, name: screen.localizedName, details: parts.joined(separator: " · "))
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    @AppStorage(SettingsKey.enabled) private var enabled = true
    @AppStorage(SettingsKey.activationModifier) private var activation = ModifierKey.shift
    @AppStorage(SettingsKey.spanModifier) private var span = ModifierKey.control
    @AppStorage(SettingsKey.showOnAllScreens) private var showOnAllScreens = true
    @AppStorage(SettingsKey.restoreSizeOnUnsnap) private var restoreSize = true
    @AppStorage(SettingsKey.spacing) private var spacing = 8.0

    var body: some View {
        Form {
            if !model.isTrusted {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility permission required").bold()
                            Text("ShiftZones needs to move and resize the windows of other apps. "
                                 + "Turn it on in System Settings › Privacy & Security › Accessibility.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Open System Settings") { Accessibility.openSystemSettings() }
                    }
                }
            }

            Section("Dragging") {
                Toggle("Zones enabled", isOn: $enabled)
                Picker("Hold to use zones", selection: $activation) {
                    ForEach(ModifierKey.allCases) { key in
                        Text(key == .none ? "No key (zones always active)" : key.label).tag(key)
                    }
                }
                Picker("Key to combine zones", selection: $span) {
                    ForEach(ModifierKey.allCases.filter { $0 != activation }) { key in
                        Text(key.label).tag(key)
                    }
                }
                LabeledContent("Spacing between zones") {
                    HStack {
                        Slider(value: $spacing, in: 0...32, step: 2)
                        Text("\(Int(spacing)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Show zones on all displays", isOn: $showOnAllScreens)
                Toggle("Restore the original size when dragging a window out of a zone", isOn: $restoreSize)
            }

            Section {
                ForEach(model.screens) { screen in
                    HStack {
                        Image(systemName: "display")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(screen.name)
                            Text(screen.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit Zones…") { model.editScreen(screen.id) }
                    }
                }
            } header: {
                Text("Displays")
            }

            Section {
                LabeledContent("Path") {
                    Text(model.filePath)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                if let error = model.fileError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { model.revealFile() }
                    Button("Open File") { model.openFile() }
                }
            } header: {
                Text("Zones file")
            } footer: {
                Text("One line per zone: x y width height, as % of the usable screen area. "
                     + "Changes apply as soon as you save; when a display is connected or disconnected "
                     + "the file is rewritten, keeping your zones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("General") {
                Toggle("Open ShiftZones at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 480)
        .onChange(of: activation) { newValue in
            if span == newValue { span = .none }
        }
    }
}
