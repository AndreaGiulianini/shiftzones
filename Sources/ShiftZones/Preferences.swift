import AppKit

enum ModifierKey: String, CaseIterable, Identifiable {
    case off, shift, option, control, command

    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .off: return []
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }

    var label: String {
        switch self {
        case .off: return "None"
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }

    func isHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        self != .off && flags.contains(self.flags)
    }
}

enum PreferencesKey {
    static let enabled = "enabled"
    static let activationModifier = "activationModifier"
    static let spanModifier = "spanModifier"
    static let showOnAllScreens = "showOnAllScreens"
    static let spacing = "spacing"
    static let restoreSizeOnUnsnap = "restoreSizeOnUnsnap"
}

/// Preferences in UserDefaults; the Settings window uses the same keys and defaults through @AppStorage.
enum Preferences {
    enum Default {
        static let enabled = true
        static let activationModifier = ModifierKey.shift
        // Not ⌥: on macOS 15+ holding ⌥ while dragging triggers the native window tiling.
        static let spanModifier = ModifierKey.control
        static let showOnAllScreens = true
        static let spacing = 8.0
        static let restoreSizeOnUnsnap = true
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            PreferencesKey.enabled: Default.enabled,
            PreferencesKey.activationModifier: Default.activationModifier.rawValue,
            PreferencesKey.spanModifier: Default.spanModifier.rawValue,
            PreferencesKey.showOnAllScreens: Default.showOnAllScreens,
            PreferencesKey.spacing: Default.spacing,
            PreferencesKey.restoreSizeOnUnsnap: Default.restoreSizeOnUnsnap,
        ])
    }

    static var enabled: Bool {
        get { defaults.bool(forKey: PreferencesKey.enabled) }
        set { defaults.set(newValue, forKey: PreferencesKey.enabled) }
    }

    /// Key to hold while dragging. `.off` = zones always active.
    static var activationModifier: ModifierKey {
        ModifierKey(rawValue: defaults.string(forKey: PreferencesKey.activationModifier) ?? "") ?? Default.activationModifier
    }

    /// Extra key that extends the selection across several zones.
    static var spanModifier: ModifierKey {
        ModifierKey(rawValue: defaults.string(forKey: PreferencesKey.spanModifier) ?? "") ?? Default.spanModifier
    }

    static var showOnAllScreens: Bool { defaults.bool(forKey: PreferencesKey.showOnAllScreens) }
    static var spacing: Double { defaults.double(forKey: PreferencesKey.spacing) }
    static var restoreSizeOnUnsnap: Bool { defaults.bool(forKey: PreferencesKey.restoreSizeOnUnsnap) }
}
