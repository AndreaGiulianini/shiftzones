import CoreGraphics

/// Tells a window drag apart from other mouse drags (text selection, resizing…).
///
/// It watches the frame of the window under the cursor across mouse events: the window is
/// being dragged when its position changes while its size stays the same.
public struct WindowDragDetector<Window> {
    public enum Phase {
        case idle
        /// Button down, no movement yet.
        case pressed
        /// The mouse is moving: waiting to see whether the window under the cursor moves too.
        case candidate(Window, initialFrame: CGRect)
        case dragging(Window)
        /// A drag that doesn't move a window.
        case ignored
    }

    public private(set) var phase: Phase = .idle

    /// Size changes up to this much are rounding noise, not a resize.
    private static var sizeTolerance: CGFloat { 1 }

    public init() {}

    public var draggedWindow: Window? {
        if case let .dragging(window) = phase { return window }
        return nil
    }

    public mutating func mouseDown() {
        phase = .pressed
    }

    public mutating func reset() {
        phase = .idle
    }

    /// Feeds a mouse movement.
    /// - Parameters:
    ///   - windowUnderCursor: looked up only on the first movement, so plain clicks cost nothing.
    ///   - frame: the current frame of a window.
    /// - Returns: the window and its frame when this movement starts dragging it.
    public mutating func mouseDragged(windowUnderCursor: () -> Window?,
                                      frame: (Window) -> CGRect?) -> (window: Window, frame: CGRect)? {
        switch phase {
        case .pressed:
            if let window = windowUnderCursor(), let initialFrame = frame(window) {
                phase = .candidate(window, initialFrame: initialFrame)
            } else {
                phase = .ignored
            }
        case let .candidate(window, initialFrame):
            // Keep checking until the button is released: the window may start moving late.
            guard let current = frame(window) else {
                phase = .ignored
                break
            }
            if abs(current.width - initialFrame.width) > Self.sizeTolerance
                || abs(current.height - initialFrame.height) > Self.sizeTolerance {
                phase = .ignored
            } else if current.origin != initialFrame.origin {
                phase = .dragging(window)
                return (window, current)
            }
        case .idle, .dragging, .ignored:
            break
        }
        return nil
    }
}
