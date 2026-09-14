import Foundation

/// A brightness transition expressed as a function of elapsed time.
///
/// The app drives this from a timer by asking "what should brightness be *now*?"
/// rather than by stepping a counter, so timer jitter and dropped frames change
/// how smooth the ramp looks but never where it ends up.
public struct BrightnessRamp {
    public let from: Float
    public let to: Float
    public let duration: TimeInterval

    public init(from: Float, to: Float, duration: TimeInterval) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    public func value(at elapsed: TimeInterval) -> Float {
        from + (to - from) * Self.eased(progress(at: elapsed))
    }

    public func isFinished(at elapsed: TimeInterval) -> Bool {
        elapsed >= duration
    }

    private func progress(at elapsed: TimeInterval) -> Float {
        guard duration > 0 else { return 1 }
        return Float(min(max(elapsed / duration, 0), 1))
    }

    /// Cubic ease-in-out. A linear ramp reads as a sudden drop that then crawls,
    /// because perceived brightness is not linear in the value we set; easing in
    /// and out keeps both ends of the fade gentle.
    private static func eased(_ t: Float) -> Float {
        if t < 0.5 { return 4 * t * t * t }
        let f = -2 * t + 2
        return 1 - (f * f * f) / 2
    }
}
