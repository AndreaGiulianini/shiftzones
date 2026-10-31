import AppKit
import OSLog
import ShiftZonesCore

/// Puts windows back on their display when it reconnects.
///
/// Many monitors disconnect while the Mac sleeps, and macOS moves their windows to the displays that are left.
/// Positions are recorded while the Mac is in use: by the time the displays report going to sleep the
/// screen is already locking, too late to read them. Once the displays are awake, connected
/// and unlocked again, the windows that ended up on another display go back.
@MainActor
final class WindowRestorer {
    private var arrangement = WindowArrangement<CGWindowID>()
    /// The displays seen by the last restore: a different set means a display has come or gone.
    private var screenIDs = Set<String>()
    private var asleep = false
    private var observers: [NSObjectProtocol] = []
    private var recordTimer: Timer?
    private var settleTimer: Timer?
    private var lastRecord = Date.distantPast
    /// It works while nobody is looking: `/usr/bin/log show --last 1d --predicate 'category == "WindowRestorer"'`.
    private let log = Logger(subsystem: "com.giulianini.ShiftZones", category: "WindowRestorer")

    /// Positions are recorded at most this often, and only if the mouse or keyboard has been used since the
    /// last time: when the displays go to sleep after a while idle, the last recording has the final positions.
    private static let recordInterval: TimeInterval = 30
    /// Monitors reconnect one at a time after waking, and macOS moves windows around meanwhile:
    /// restore only once the displays have stopped changing for this long.
    private static let settleDelay: TimeInterval = 2
    /// Some apps finish moving to the new display late, so the frame is applied again after this delay.
    private static let reapplyDelay: TimeInterval = 0.5

    private var connectedScreenIDs: Set<String> { Set(NSScreen.screens.map(\.stableID)) }

    private var isScreenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    private var usedSinceLastRecord: Bool {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return idle < Date().timeIntervalSince(lastRecord)
    }

    func start() {
        guard observers.isEmpty else { return }
        screenIDs = connectedScreenIDs
        let workspace = NSWorkspace.shared.notificationCenter
        // Going to sleep without turning the displays off first (lid, Apple menu) only sends willSleep.
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysDidSleep() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.displaysDidSleep() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysDidWake() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.displaysDidWake() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.scheduleRestore() }
        recordTimer = Timer.scheduledTimer(withTimeInterval: Self.recordInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
        // Lets macOS run it together with other wake-ups.
        recordTimer?.tolerance = Self.recordInterval / 3
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor @Sendable (WindowRestorer) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        })
    }

    private func displaysDidSleep() {
        guard !asleep else { return }
        asleep = true
        settleTimer?.invalidate()
        settleTimer = nil
        log.notice("Displays asleep: \(self.arrangement.placements.count) windows recorded")
    }

    private func displaysDidWake() {
        asleep = false
        scheduleRestore()
    }

    /// Recording pauses until the restore: until then the windows may be where macOS moved them.
    private func scheduleRestore() {
        // While asleep monitors come and go (e.g. during Power Nap): nothing to do until wake.
        guard !asleep else { return }
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        }
    }

    private func record() {
        guard !asleep, settleTimer == nil, usedSinceLastRecord, !isScreenLocked, Preferences.restoreWindowsOnReconnect
        else { return }
        let connected = connectedScreenIDs
        // A display came or went and the notification hasn't arrived yet: windows may have moved already.
        guard connected == screenIDs else {
            scheduleRestore()
            return
        }
        var placements: [CGWindowID: WindowArrangement<CGWindowID>.Placement] = [:]
        for window in ListedWindow.onScreen() {
            guard let screen = ScreenGeometry.screen(containing: CGPoint(x: window.frame.midX, y: window.frame.midY))
            else { continue }
            placements[window.id] = .init(screenID: screen.stableID,
                                          frame: window.frame.offsetBy(dx: -screen.axFrame.minX, dy: -screen.axFrame.minY))
        }
        arrangement.record(placements, connected: connected)
        lastRecord = Date()
    }

    private func restore() {
        settleTimer = nil
        guard !asleep else { return }
        // Windows can't be moved behind the lock screen: try again until it's unlocked.
        guard !isScreenLocked else {
            scheduleRestore()
            return
        }
        let connected = connectedScreenIDs
        screenIDs = connected
        // Windows have moved without any input: the next recording mustn't be skipped.
        lastRecord = .distantPast
        guard Preferences.restoreWindowsOnReconnect, Accessibility.isTrusted else {
            arrangement = WindowArrangement()
            return
        }
        let listed = Dictionary(ListedWindow.onScreen().map { ($0.id, $0) }) { front, _ in front }
        let misplaced = arrangement.takeMisplaced(connected: connected) { id in
            guard let frame = listed[id]?.frame else { return nil }
            return ScreenGeometry.screen(containing: CGPoint(x: frame.midX, y: frame.midY))?.stableID
        }
        log.notice("""
            Displays settled: \(misplaced.count) windows to put back, \
            \(self.arrangement.placements.count) waiting for a display
            """)
        for (id, placement) in misplaced {
            guard let window = listed[id]?.axWindow, !window.isFullScreen,
                  let screen = ScreenGeometry.screen(withID: placement.screenID)
            else { continue }
            let frame = placement.frame.offsetBy(dx: screen.axFrame.minX, dy: screen.axFrame.minY)
            window.setFrame(frame)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reapplyDelay) {
                if let current = window.frame, !current.isClose(to: frame) {
                    window.setFrame(frame)
                }
            }
        }
    }
}
