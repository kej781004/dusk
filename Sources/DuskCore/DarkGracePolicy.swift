import Foundation

public enum DarkGraceAction: Equatable {
    /// Nothing to do: either the screen is still being held at zero, or the grace
    /// period is running and has not expired.
    case hold
    /// The brightness moved under Dusk's feet. Hand the screen over and start the
    /// grace period from now.
    case yield
    /// The grace period has run out. Take the screen back.
    case redim
}

/// Pure decision logic for the peek window: while Dusk is holding the screen
/// dark, reaching for the brightness keys buys you a few minutes of visible
/// screen before it fades back down.
///
/// This is the rule the old escape hatch used to break. That hatch handed the
/// screen back permanently, because a black panel hides the menu bar and the
/// brightness key was the only way out you can find without seeing it. The way
/// out is now to switch Dusk off while the screen is up — so this must never
/// return `.redim` on a shorter clock than a person needs to reach the menu bar.
public enum DarkGracePolicy {
    /// - Parameters:
    ///   - level: brightness as just read, 0...1.
    ///   - graceLevel: the level the peek window started at, or nil when the
    ///     screen is still being held dark.
    ///   - elapsed: seconds since the peek window began. Ignored when
    ///     `graceLevel` is nil.
    ///   - delay: how long a peek lasts.
    ///   - darkCeiling: below this the screen reads as off, so anything above it
    ///     means the level came back from somewhere other than Dusk.
    ///   - threshold: a brightness key press moves the level by 1/16, so a gap
    ///     this size during a peek means another deliberate press rather than the
    ///     ambient sensor drifting.
    public static func decide(level: Float,
                              graceLevel: Float?,
                              elapsed: TimeInterval,
                              delay: TimeInterval,
                              darkCeiling: Float,
                              threshold: Float) -> DarkGraceAction {
        guard let graceLevel else {
            return level > darkCeiling ? .yield : .hold
        }
        // Every further adjustment pushes the deadline back, so the screen does
        // not go out from under someone who is plainly still using it.
        if abs(level - graceLevel) > threshold { return .yield }
        return elapsed >= delay ? .redim : .hold
    }
}
