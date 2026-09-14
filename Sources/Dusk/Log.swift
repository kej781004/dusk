import Foundation
import os

/// Dusk's unified-log channel.
///
/// Dusk decides things while nobody is watching — it suspends itself on a dying
/// battery with the lid shut, and resumes once the charger is back. When one of
/// those passes goes wrong there is nothing to look at afterwards: `pmset -g log`
/// records power *events*, not the `disablesleep` writes Dusk makes, and a menu
/// bar app has no window to print to. Every incident then comes down to guessing
/// from battery percentages hours later.
///
/// So every state transition and every failure lands here. Read it back with:
///
///     log show --predicate 'subsystem == "parkchanbin.Dusk"' --last 1d --info
enum Log {
    /// Also the value in the `log show` predicate above; keep the two in step.
    private static let subsystem = "parkchanbin.Dusk"

    static let power = Logger(subsystem: subsystem, category: "power")
    static let battery = Logger(subsystem: subsystem, category: "battery")
    static let notify = Logger(subsystem: subsystem, category: "notify")
}
