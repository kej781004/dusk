import Foundation

/// Wall-clock countdown behind the "N분 동안 켜두기" presets. Deadline-based
/// rather than interval-based, so the countdown stays honest if the machine
/// sleeps and wakes mid-timer.
///
/// Scheduled on the main run loop, so every callback lands on the main thread —
/// stated with `MainActor.assumeIsolated` rather than left implicit, the way the
/// ramp, watchdog and battery-recheck timers do it.
@MainActor
final class AutoOffTimer {

    /// Called once the deadline has passed, and again on every tick after that
    /// until the owner calls `cancel()`.
    ///
    /// Expiry deliberately does *not* cancel the countdown. Turning Dusk off is
    /// a `pmset` round-trip that can be deferred (another write in flight) or
    /// fail outright, and this used to cancel first and call second: one dropped
    /// attempt left Dusk switched on with no countdown left to fire again, so
    /// the Mac never slept. Now the deadline stays armed and every tick is
    /// another attempt; the owner cancels once the machine has actually moved.
    var onExpire: (() -> Void)?
    /// Called on each tick while still counting down, so the UI can redraw the
    /// remaining time.
    var onTick: (() -> Void)?

    /// How often the deadline is checked — and, past it, how often the off is
    /// retried.
    private static let tickInterval: TimeInterval = 15

    private var deadline: Date?
    private var ticker: Timer?

    var isRunning: Bool { deadline != nil }

    /// Seconds left, or nil when no countdown is running.
    var remaining: TimeInterval? {
        guard let deadline else { return nil }
        return max(0, deadline.timeIntervalSinceNow)
    }

    func start(minutes: Int) {
        cancel()
        deadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)

        let ticker = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common modes so the countdown keeps ticking while the menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
    }

    private func tick() {
        guard let deadline else { return }
        guard Date() >= deadline else {
            onTick?()
            return
        }
        onExpire?()
    }
}
