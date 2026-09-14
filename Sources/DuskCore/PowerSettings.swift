import Foundation

/// Parsers for the two `pmset` readouts Dusk cares about.
///
/// Both settings are read back rather than assumed, because `pmset` is a system
/// setting that survives Dusk quitting, crashing, or being force-killed. On
/// launch Dusk has to find out what a previous run left behind.
public enum PowerSettings {

    /// Reads `SleepDisabled` out of `pmset -g`, which prints it under the
    /// "System-wide power settings:" header as a single global flag.
    ///
    /// Note this is *not* in `pmset -g custom` — that lists only the
    /// per-power-source settings, and disablesleep is not one of them.
    ///
    /// Returns nil when the output carried no SleepDisabled line at all.
    public static func parse(sleepDisabled output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = self.fields(of: line)
            guard fields.count >= 2, fields[0] == "SleepDisabled" else { continue }
            guard let value = Int(fields[1]) else { continue }
            return value != 0
        }
        return nil
    }

    /// Reads low power mode out of `pmset -g custom`, which lists one block per
    /// power source ("Battery Power:", "AC Power:").
    ///
    /// Dusk writes every source at once with `pmset -a`, so it only reports "on"
    /// when every source agrees. A mixed reading — which is the machine's default
    /// state — counts as off, and one click brings both sources to on.
    ///
    /// Returns nil when the output carried no low power mode line at all.
    public static func parse(lowPowerMode output: String) -> Bool? {
        let values = output
            .split(separator: "\n")
            .compactMap { line -> Int? in
                let fields = self.fields(of: line)
                guard fields.count >= 2, fields[0] == "lowpowermode" else { return nil }
                return Int(fields[1])
            }

        guard !values.isEmpty else { return nil }
        return values.allSatisfy { $0 != 0 }
    }

    /// Splits a pmset line into words.
    ///
    /// pmset is not consistent about its separators: the per-source settings are
    /// padded out with spaces, but the system-wide block uses tabs. Splitting on
    /// spaces alone silently reads every SleepDisabled line as absent.
    private static func fields(of line: Substring) -> [Substring] {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" })
    }
}
