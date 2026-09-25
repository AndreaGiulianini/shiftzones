import AppKit

enum ModifierKey: String, CaseIterable, Identifiable {
    case none, shift, option, control, command

    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .none: return []
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }

    var label: String {
        switch self {
        case .none: return "None"
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }

    func isHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        self != .none && flags.contains(self.flags)
    }
}

enum SettingsKey {
    static let enabled = "enabled"
    static let activationModifier = "activationModifier"
    static let spanModifier = "spanModifier"
    static let showOnAllScreens = "showOnAllScreens"
    static let spacing = "spacing"
    static let restoreSizeOnUnsnap = "restoreSizeOnUnsnap"
}

/// Preferences in UserDefaults; the Settings window uses the same keys through @AppStorage.
enum Settings {
    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.enabled: true,
            SettingsKey.activationModifier: ModifierKey.shift.rawValue,
            // Not ⌥: on macOS 15+ holding ⌥ while dragging triggers the native window tiling.
            SettingsKey.spanModifier: ModifierKey.control.rawValue,
            SettingsKey.showOnAllScreens: true,
            SettingsKey.spacing: 8.0,
            SettingsKey.restoreSizeOnUnsnap: true,
        ])
    }

    static var enabled: Bool {
        get { defaults.bool(forKey: SettingsKey.enabled) }
        set { defaults.set(newValue, forKey: SettingsKey.enabled) }
    }

    /// Key to hold while dragging. `.none` = zones always active.
    static var activationModifier: ModifierKey {
        ModifierKey(rawValue: defaults.string(forKey: SettingsKey.activationModifier) ?? "") ?? .shift
    }

    /// Extra key that extends the selection across several zones.
    static var spanModifier: ModifierKey {
        ModifierKey(rawValue: defaults.string(forKey: SettingsKey.spanModifier) ?? "") ?? .control
    }

    static var showOnAllScreens: Bool { defaults.bool(forKey: SettingsKey.showOnAllScreens) }
    static var spacing: Double { defaults.double(forKey: SettingsKey.spacing) }
    static var restoreSizeOnUnsnap: Bool { defaults.bool(forKey: SettingsKey.restoreSizeOnUnsnap) }
}
