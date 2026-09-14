import Foundation

/// The low-battery slider's number line: 0…100 in steps of 5, where 0 means the
/// feature is off entirely.
///
/// Pure arithmetic, deliberately kept out of the view so the snapping can be
/// tested without a mouse. Every value that enters or leaves the track goes
/// through here, so the knob can never come to rest between two stops.
public enum ThresholdScale {
    public static let minimum = 0
    public static let maximum = 100
    public static let step = 5

    /// One dot per stop under the track.
    public static var stopCount: Int { (maximum - minimum) / step + 1 }

    /// Only these stops get a printed number. All eleven multiples of ten would
    /// make the menu half again as wide as the rows above it.
    public static let labelledValues = [0, 25, 50, 75, 100]

    /// Rounds to the nearest stop and clamps to the ends.
    public static func snap(_ value: Int) -> Int {
        let clamped = min(max(value, minimum), maximum)
        let steps = Int((Double(clamped - minimum) / Double(step)).rounded())
        return min(minimum + steps * step, maximum)
    }

    /// Where a value sits along the track, 0…1.
    public static func fraction(of value: Int) -> Double {
        Double(snap(value) - minimum) / Double(maximum - minimum)
    }

    /// The stop nearest a point on the track. Fractions outside 0…1 clamp, so a
    /// drag that leaves the view still tracks the nearer end rather than jumping.
    public static func value(atFraction fraction: Double) -> Int {
        let clamped = min(max(fraction, 0), 1)
        return snap(minimum + Int((clamped * Double(maximum - minimum)).rounded()))
    }
}
