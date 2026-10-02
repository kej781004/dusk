import Foundation

/// The stops on the popover's duration ruler.
///
/// Evenly spaced on screen but not in time: five-minute steps to an hour, then
/// fifteen-minute steps to four hours, then "until turned off". Short durations
/// are the common choice, so the first hour gets the left half of the ruler.
///
/// Pure arithmetic, kept out of the view so the snapping can be tested without
/// a mouse — the same reason `ThresholdScale` exists.
public enum DurationScale {
    /// One labelled stop under the ruler.
    public struct Label: Hashable {
        public let index: Int
        public let text: String
    }

    /// Minutes at each stop; `nil` is the last stop, "until turned off".
    public static let stops: [Int?] =
        Array(stride(from: 5, through: 60, by: 5)) + Array(stride(from: 75, through: 240, by: 15)) + [nil]

    public static var count: Int { stops.count }
    public static var lastIndex: Int { stops.count - 1 }

    public static let labels: [Label] = [
        Label(index: 0, text: "5m"), Label(index: 5, text: "30m"), Label(index: 11, text: "1h"),
        Label(index: 15, text: "2h"), Label(index: 23, text: "4h"), Label(index: 24, text: "∞"),
    ]

    /// Where a stop sits along the ruler, 0…1.
    public static func fraction(forStop index: Int) -> Double {
        Double(min(max(index, 0), lastIndex)) / Double(lastIndex)
    }

    /// The stop nearest a point on the ruler. Positions outside 0…1 clamp, so a
    /// drag that leaves the ruler still tracks the nearer end.
    public static func nearestStop(toFraction fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * Double(lastIndex)).rounded())
    }

    /// Minutes at a stop, or nil for "until turned off".
    public static func minutes(atStop index: Int) -> Int? {
        stops[min(max(index, 0), lastIndex)]
    }

    /// The stop showing a duration: exact where one exists, otherwise the
    /// nearest, so any stored value still lands somewhere sensible. nil is the
    /// last stop.
    public static func stop(forMinutes minutes: Int?) -> Int {
        guard let minutes else { return lastIndex }
        var best = 0
        var bestDistance = Int.max
        for (index, value) in stops.enumerated() {
            guard let value else { continue }
            let distance = abs(value - minutes)
            if distance < bestDistance { best = index; bestDistance = distance }
        }
        return best
    }
}
