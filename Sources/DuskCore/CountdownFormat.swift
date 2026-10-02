import Foundation

/// A running countdown the way the popover's numerals show it.
public enum CountdownFormat {
    /// `12:00`, `1:05:00`, `0:59`. Rounds up to the whole second, so a countdown
    /// with any time left never reads `0:00`; one already over never goes
    /// negative.
    public static func string(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
