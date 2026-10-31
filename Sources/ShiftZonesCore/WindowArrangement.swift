import CoreGraphics

/// The display each window was on, to put the windows back after macOS has moved them away.
///
/// Many monitors drop off the connection while the Mac sleeps: macOS then moves their windows to the
/// displays that are left, and doesn't reliably move them back when the monitors return.
public struct WindowArrangement<Window: Hashable> {
    public struct Placement: Equatable {
        public let screenID: String
        /// Frame relative to the top-left corner of the display, so it survives arrangement changes.
        public let frame: CGRect

        public init(screenID: String, frame: CGRect) {
            self.screenID = screenID
            self.frame = frame
        }
    }

    public private(set) var placements: [Window: Placement] = [:]

    public init() {}

    public var isEmpty: Bool { placements.isEmpty }

    /// Records where the windows are now. Placements on displays that aren't connected are kept:
    /// those windows have been moved away by macOS and still have to go back.
    public mutating func record(_ current: [Window: Placement], connected: Set<String>) {
        placements = placements
            .filter { !connected.contains($0.value.screenID) }
            .merging(current) { waiting, _ in waiting }
    }

    /// The windows to put back: the ones now on another display than their own, if theirs is connected.
    /// Windows still on their display are left alone, even if they have been moved within it.
    /// Every placement on a connected display is then forgotten; the others wait for their display.
    /// - Parameter currentScreen: the display a window is on now, nil if it must not be touched.
    public mutating func takeMisplaced(connected: Set<String>,
                                       currentScreen: (Window) -> String?) -> [(window: Window, placement: Placement)] {
        var misplaced: [(window: Window, placement: Placement)] = []
        for (window, placement) in placements where connected.contains(placement.screenID) {
            if let current = currentScreen(window), current != placement.screenID {
                misplaced.append((window, placement))
            }
        }
        placements = placements.filter { !connected.contains($0.value.screenID) }
        return misplaced
    }
}
