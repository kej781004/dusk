import Foundation
import DuskCore

print("BrightnessRamp")

Check.test("starts at the origin brightness") {
    let r = BrightnessRamp(from: 0.8, to: 0.0, duration: 3.0)
    Check.close(r.value(at: 0), 0.8)
}

Check.test("lands exactly on the target at the end of the duration") {
    let r = BrightnessRamp(from: 0.8, to: 0.0, duration: 3.0)
    Check.close(r.value(at: 3.0), 0.0)
}

Check.test("clamps past the end so timer overshoot cannot undershoot the target") {
    let r = BrightnessRamp(from: 0.8, to: 0.0, duration: 3.0)
    Check.close(r.value(at: 4.7), 0.0)
}

Check.test("clamps before the start") {
    let r = BrightnessRamp(from: 0.8, to: 0.0, duration: 3.0)
    Check.close(r.value(at: -1.0), 0.8)
}

Check.test("decreases monotonically over a dim") {
    let r = BrightnessRamp(from: 0.8125, to: 0.0, duration: 3.0)
    var previous = Float(2.0)
    for i in 0...180 {
        let v = r.value(at: Double(i) / 60.0)
        Check.isTrue(v <= previous, "step \(i): \(v) should be <= \(previous)")
        previous = v
    }
}

Check.test("increases monotonically over a restore") {
    let r = BrightnessRamp(from: 0.0, to: 0.8125, duration: 0.8)
    var previous = Float(-1.0)
    for i in 0...48 {
        let v = r.value(at: Double(i) / 60.0)
        Check.isTrue(v >= previous, "step \(i): \(v) should be >= \(previous)")
        previous = v
    }
}

Check.test("eases symmetrically so the midpoint is halfway") {
    let r = BrightnessRamp(from: 1.0, to: 0.0, duration: 3.0)
    Check.close(r.value(at: 1.5), 0.5)
}

Check.test("eases in, so the first quarter moves less than a quarter of the way") {
    let r = BrightnessRamp(from: 1.0, to: 0.0, duration: 4.0)
    // Linear would sit at 0.75 after a quarter of the ramp. Easing starts slower,
    // so more brightness must remain.
    Check.isTrue(r.value(at: 1.0) > 0.75, "value at 25% was \(r.value(at: 1.0)), expected > 0.75")
}

Check.test("reports finished only at or past the duration") {
    let r = BrightnessRamp(from: 0.8, to: 0.0, duration: 3.0)
    Check.equal(r.isFinished(at: 2.99), false, "just before the end")
    Check.equal(r.isFinished(at: 3.0), true, "exactly at the end")
    Check.equal(r.isFinished(at: 9.0), true, "past the end")
}

Check.test("a zero-duration ramp is finished immediately at the target") {
    let r = BrightnessRamp(from: 0.8, to: 0.0, duration: 0)
    Check.equal(r.isFinished(at: 0), true)
    Check.close(r.value(at: 0), 0.0)
}

print("")
print("PowerSettings — SleepDisabled")

// Real output shape from `pmset -g` on this Mac. SleepDisabled sits under the
// system-wide header, not in the per-source list.
let pmsetGlobal = """
System-wide power settings:
 SleepDisabled\t\t0
Currently in use:
 standby              1
 sleep                1 (sleep prevented by powerd)
 lowpowermode         0
"""

Check.test("reads sleep as enabled when SleepDisabled is 0") {
    Check.equal(PowerSettings.parse(sleepDisabled: pmsetGlobal), false)
}

Check.test("reads sleep as disabled when SleepDisabled is 1") {
    let out = pmsetGlobal.replacingOccurrences(of: "SleepDisabled\t\t0",
                                               with: "SleepDisabled\t\t1")
    Check.equal(PowerSettings.parse(sleepDisabled: out), true)
}

Check.test("returns nil when pmset reported no SleepDisabled line") {
    // `pmset -g custom` is the wrong command for this setting; catching that here
    // is cheaper than finding out at run time that the switch never reads back.
    Check.equal(PowerSettings.parse(sleepDisabled: "Battery Power:\n lowpowermode 0\n"), nil)
}

Check.test("is not confused by the sleep line that names its blockers") {
    // " sleep 1 (sleep prevented by powerd)" must not be mistaken for the flag.
    Check.equal(PowerSettings.parse(sleepDisabled: "Currently in use:\n sleep 1 (sleep prevented by powerd)\n"), nil)
}

print("")
print("PowerSettings — lowpowermode")

// Real output shape from `pmset -g custom` on this Mac.
let mixedOutput = """
Battery Power:
 lowpowermode         0
 displaysleep         2
AC Power:
 lowpowermode         1
 displaysleep         10
"""

Check.test("reads off when every power source has low power mode off") {
    let out = mixedOutput.replacingOccurrences(of: "lowpowermode         1",
                                               with: "lowpowermode         0")
    Check.equal(PowerSettings.parse(lowPowerMode: out), false)
}

Check.test("reads on only when every power source has low power mode on") {
    let out = mixedOutput.replacingOccurrences(of: "lowpowermode         0",
                                               with: "lowpowermode         1")
    Check.equal(PowerSettings.parse(lowPowerMode: out), true)
}

Check.test("reads off when only some power sources have it on") {
    // The toggle writes every source with `pmset -a`, so a mixed reading is not "on".
    Check.equal(PowerSettings.parse(lowPowerMode: mixedOutput), false)
}

Check.test("returns nil when pmset reported no low power mode line") {
    Check.equal(PowerSettings.parse(lowPowerMode: "Battery Power:\n sleep 1\n"), nil)
}

print("")
print("DuskState")

Check.test("is idle when every switch is off") {
    Check.equal(DuskState(awake: false, lowPower: false, dark: false).isActive, false)
}

Check.test("is active when only the lid switch is on") {
    Check.equal(DuskState(awake: true, lowPower: false, dark: false).isActive, true)
}

Check.test("is active when only the screen is dark") {
    Check.equal(DuskState(awake: false, lowPower: false, dark: true).isActive, true)
}

Check.test("is active when only low power mode is on") {
    Check.equal(DuskState(awake: false, lowPower: true, dark: false).isActive, true)
}

print("")
print("DuskState switching order")

Check.test("brings the screen back first when switching everything off") {
    // A failed pmset call raises an alert. Doing that before the screen is
    // restored would put a dialog on a black screen and delay the fade back up.
    Check.equal(DuskState(awake: false, lowPower: false, dark: false).restoresScreenFirst, true)
}

Check.test("settles the power switches first when switching on") {
    // Same dialog, opposite reason: it has to be readable while the screen is
    // still bright, before the fade to black starts.
    Check.equal(DuskState(awake: true, lowPower: true, dark: true).restoresScreenFirst, false)
}

print("")
print("AutoOffPolicy")

Check.test("does nothing when the feature is switched off") {
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: false, percent: 3,
                                     onAC: false, threshold: 0), .none)
}

Check.test("suspends once the charge falls below the floor on battery") {
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: false, percent: 9,
                                     onAC: false, threshold: 10), .suspend)
}

Check.test("does not suspend while plugged in") {
    // The whole point is a lid-shut Mac running flat; on AC there is nothing to save.
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: false, percent: 3,
                                     onAC: true, threshold: 10), .none)
}

Check.test("does not suspend when the user never asked for Dusk") {
    Check.equal(AutoOffPolicy.decide(intent: false, suspended: false, percent: 3,
                                     onAC: false, threshold: 10), .none)
}

Check.test("does not suspend when the user overrode the floor on purpose") {
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: false, overridden: true,
                                     percent: 3, onAC: false, threshold: 10), .none)
}

Check.test("resumes only once charging has cleared the floor plus hysteresis") {
    // At exactly the threshold the charge is still within noise of the trip point,
    // so resuming there would flap the switch.
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 10,
                                     onAC: true, threshold: 10), .none)
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 15,
                                     onAC: true, threshold: 10), .resume)
}

Check.test("still resumes at a full battery when the floor is set near the top") {
    // The slider goes to 100, where threshold + hysteresis would ask for 105% —
    // a charge no battery reports, so one suspension would have been permanent.
    for threshold in [96, 100] {
        Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 100,
                                         onAC: true, threshold: threshold), .resume,
                    "threshold \(threshold)")
    }
}

Check.test("a near-full floor still waits for the charge to come back") {
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 99,
                                     onAC: true, threshold: 100), .none)
}

Check.test("does not resume while still on battery") {
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 90,
                                     onAC: false, threshold: 10), .none)
}

Check.test("an override survives the discharge and ends at the charger") {
    Check.equal(AutoOffPolicy.shouldKeepOverride(true, onAC: false), true)
    Check.equal(AutoOffPolicy.shouldKeepOverride(true, onAC: true), false)
    Check.equal(AutoOffPolicy.shouldKeepOverride(false, onAC: false), false)
}

print("")
print("PowerSettings against live pmset output")

/// Runs a command and returns stdout, or nil if it could not be run.
func capture(_ path: String, _ arguments: [String]) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(data: data, encoding: .utf8)
}

// The fixtures above are hand-copied, so they cannot catch pmset changing its
// mind about separators or headings — which is exactly how the SleepDisabled
// parser shipped broken the first time (tabs, not spaces). Read the real thing.
Check.test("finds SleepDisabled in this machine's actual `pmset -g`") {
    guard let output = capture("/usr/bin/pmset", ["-g"]) else {
        return Check.fail("could not run pmset -g")
    }
    Check.isTrue(PowerSettings.parse(sleepDisabled: output) != nil,
                 "parser returned nil for live output:\n\(output)")
}

Check.test("finds lowpowermode in this machine's actual `pmset -g custom`") {
    guard let output = capture("/usr/bin/pmset", ["-g", "custom"]) else {
        return Check.fail("could not run pmset -g custom")
    }
    Check.isTrue(PowerSettings.parse(lowPowerMode: output) != nil,
                 "parser returned nil for live output:\n\(output)")
}

print("")
print("ThresholdScale")

Check.test("snaps to the nearest stop") {
    Check.equal(ThresholdScale.snap(0), 0)
    Check.equal(ThresholdScale.snap(12), 10)
    Check.equal(ThresholdScale.snap(13), 15)
    Check.equal(ThresholdScale.snap(97), 95)
    Check.equal(ThresholdScale.snap(98), 100)
}

Check.test("clamps values off either end of the track") {
    Check.equal(ThresholdScale.snap(-40), 0)
    Check.equal(ThresholdScale.snap(999), 100)
}

Check.test("every stop is a multiple of the step, and lands on itself") {
    for index in 0..<ThresholdScale.stopCount {
        let stop = index * ThresholdScale.step
        Check.equal(ThresholdScale.snap(stop), stop, "stop \(stop)")
    }
}

Check.test("draws one dot per stop, ends included") {
    Check.equal(ThresholdScale.stopCount, 21)
}

Check.test("puts the ends of the track at the ends of the range") {
    Check.close(Float(ThresholdScale.fraction(of: 0)), 0)
    Check.close(Float(ThresholdScale.fraction(of: 100)), 1)
    Check.close(Float(ThresholdScale.fraction(of: 50)), 0.5)
}

Check.test("a drag anywhere on the track lands on a stop, never between two") {
    // 0.5pt steps across a 200pt track: no reachable pointer position may produce
    // a value the knob cannot be drawn at.
    for step in 0...400 {
        let value = ThresholdScale.value(atFraction: Double(step) / 400.0)
        Check.equal(value % ThresholdScale.step, 0, "fraction \(Double(step) / 400.0) gave \(value)")
    }
}

Check.test("a drag that leaves the view clamps to the nearer end") {
    Check.equal(ThresholdScale.value(atFraction: -3.0), 0)
    Check.equal(ThresholdScale.value(atFraction: 4.0), 100)
}

Check.test("round-trips every stop through the track and back") {
    for index in 0..<ThresholdScale.stopCount {
        let stop = index * ThresholdScale.step
        Check.equal(ThresholdScale.value(atFraction: ThresholdScale.fraction(of: stop)), stop,
                    "stop \(stop)")
    }
}

Check.test("every labelled number is a stop the knob can reach") {
    for value in ThresholdScale.labelledValues {
        Check.equal(ThresholdScale.snap(value), value, "label \(value)")
    }
}

print("")
print("DarkGracePolicy — the peek window")

// The controller's own constants, so the tests exercise the real numbers.
let ceiling: Float = 0.05
let bump: Float = 0.05
let peek: TimeInterval = 5 * 60

func decide(level: Float, since: Float?, elapsed: TimeInterval = 0) -> DarkGraceAction {
    DarkGracePolicy.decide(level: level, graceLevel: since, elapsed: elapsed,
                           delay: peek, darkCeiling: ceiling, threshold: bump)
}

Check.test("holds the screen down while it is still dark") {
    Check.equal(decide(level: 0, since: nil), .hold)
}

Check.test("holds through sensor noise below the dark ceiling") {
    Check.equal(decide(level: 0.04, since: nil), .hold)
}

Check.test("yields the moment a brightness key lifts the level clear of the ceiling") {
    // One press is 1/16, comfortably past the 0.05 ceiling.
    Check.equal(decide(level: 0.0625, since: nil), .yield)
}

Check.test("keeps holding the peek open before the delay is up") {
    Check.equal(decide(level: 0.5, since: 0.5, elapsed: peek - 1), .hold)
}

Check.test("re-dims once the delay has passed") {
    Check.equal(decide(level: 0.5, since: 0.5, elapsed: peek), .redim)
}

Check.test("re-dims on a late tick, so a dropped beat cannot strand the screen bright") {
    Check.equal(decide(level: 0.5, since: 0.5, elapsed: peek * 3), .redim)
}

Check.test("a further press pushes the deadline back instead of re-dimming") {
    // Four seconds short of the deadline, the user reaches for the keys again.
    Check.equal(decide(level: 0.5 + 0.0625, since: 0.5, elapsed: peek - 4), .yield)
}

Check.test("a further press pushes the deadline back even once the delay has passed") {
    // The press wins over the expiry: yielding restarts the clock, so the screen
    // never blacks out in the same beat the user is adjusting it.
    Check.equal(decide(level: 0.5 + 0.0625, since: 0.5, elapsed: peek + 10), .yield)
}

Check.test("turning the brightness down during a peek also restarts the clock") {
    Check.equal(decide(level: 0.5 - 0.0625, since: 0.5, elapsed: 60), .yield)
}

Check.test("drift smaller than a key press does not restart the clock") {
    Check.equal(decide(level: 0.53, since: 0.5, elapsed: peek), .redim)
}

Check.test("a peek that the user themselves took to black still re-dims on time") {
    // Dropping to zero by hand leaves the level under the ceiling, but the peek
    // is keyed off the recorded start level, not the ceiling, so it still ends.
    Check.equal(decide(level: 0.0, since: 0.02, elapsed: peek), .redim)
}

Check.summarize()
