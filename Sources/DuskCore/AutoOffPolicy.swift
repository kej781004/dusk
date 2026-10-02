import Foundation

public enum AutoOffAction: Equatable {
    case none
    case suspend
    case resume
}

/// Pure decision logic for battery-based auto-off. No IOKit, no side effects —
/// given the current state it returns the action to take.
///
/// Ported from Awayke, which needed it for the same reason Dusk does: keeping a
/// Mac awake with the lid shut is exactly the situation where a flat battery
/// goes unnoticed.
public enum AutoOffPolicy {
    /// - Parameters:
    ///   - intent: the user wants Dusk on.
    ///   - suspended: battery auto-off is currently holding Dusk off.
    ///   - overridden: the user manually turned Dusk on while already below the
    ///     floor, so auto-off stands down for this discharge.
    ///   - percent: current battery charge, 0...100.
    ///   - onAC: running on AC / external power.
    ///   - threshold: 0 disables the feature; otherwise the low-battery floor.
    ///   - hysteresis: extra points above threshold required to resume, so a
    ///     charge hovering on the line does not flap the switch. Never asks for
    ///     more than a full battery.
    public static func decide(intent: Bool,
                              suspended: Bool,
                              overridden: Bool = false,
                              percent: Int,
                              onAC: Bool,
                              threshold: Int,
                              hysteresis: Int = 5) -> AutoOffAction {
        guard threshold > 0 else { return .none }

        if !suspended, intent, !overridden,
           isBelowFloor(percent: percent, onAC: onAC, threshold: threshold) {
            return .suspend
        }
        if suspended, onAC, percent >= resumeLevel(threshold: threshold, hysteresis: hysteresis) {
            return .resume
        }
        return .none
    }

    /// Running on battery, under the floor. The charge half of what `decide`
    /// suspends on, exposed because callers need to ask the same question —
    /// notably to tell a deliberate override from an ordinary switch-on — and a
    /// second copy of the predicate would be one nothing tests.
    public static func isBelowFloor(percent: Int, onAC: Bool, threshold: Int) -> Bool {
        threshold > 0 && !onAC && percent < threshold
    }

    /// A manual override lasts only as long as the current discharge. Reaching
    /// AC ends it, so auto-off re-arms for the next one.
    public static func shouldKeepOverride(_ overridden: Bool, onAC: Bool) -> Bool {
        overridden && !onAC
    }

    /// The charge at which a suspended Dusk comes back on: the floor plus the
    /// hysteresis. Exposed so the popover can say "resumes past 25%" from the
    /// same number `decide` acts on, rather than a second copy that could drift.
    ///
    /// Capped at a full battery: the threshold is a slider, and a floor set near
    /// the top would otherwise ask for a charge above 100% before Dusk could
    /// ever come back — one suspension and it would never resume.
    public static func resumeLevel(threshold: Int, hysteresis: Int = 5) -> Int {
        min(threshold + hysteresis, 100)
    }
}
