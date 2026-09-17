import AppKit
import DuskCore

/// Owns the three switches, the brightness fade between them, and the sleep /
/// wake bookkeeping that keeps the two in agreement.
@MainActor
final class DuskController {
    /// How long the screen takes to fade down.
    private static let dimDuration: TimeInterval = 3.0
    /// Coming back is deliberately quicker — you turn it off because you want to see.
    private static let restoreDuration: TimeInterval = 0.8
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    /// A brightness key press moves the level by 1/16. Frame-to-frame lag during a
    /// ramp is under 0.005, and the ambient sensor drifts slowly, so a gap this size
    /// means a person reached for the keyboard.
    private static let interventionThreshold: Float = 0.05
    /// Below this the screen reads as off, so anything above it means the level
    /// came back from somewhere other than Dusk.
    private static let darkCeiling: Float = 0.05
    private static let watchdogInterval: TimeInterval = 0.4
    /// How long the screen stays yours after you reach for the brightness keys,
    /// before Dusk fades it back down. Long enough to read something and, if you
    /// meant to stop entirely, to aim at the menu bar and switch Dusk off — but
    /// no longer than that: five minutes of a bright screen after a glance reads
    /// as Dusk having given up, and the point of the dark switch is that the
    /// screen goes back to black on its own.
    private static let peekDuration: TimeInterval = 2 * 60
    /// Used when the level captured at dim time was already at the floor, so that
    /// turning Dusk off always leaves a visible screen.
    private static let fallbackRestoreLevel: Float = 0.5
    /// Waking a panel is not instant. Re-applying the dark level immediately can
    /// land before the display is back and get overwritten, so it waits.
    private static let wakeSettleDelay: TimeInterval = 1.0

    private static let restoreLevelKey = "brightnessRestoreLevel"
    private static let wasDarkKey = "wasDarkAtExit"

    private(set) var state = DuskState(awake: false, lowPower: false, dark: false)
    var onChange: (() -> Void)?

    private let brightness = DisplayBrightness()
    private let wakeKeeper = DisplayWakeKeeper()

    private var rampTimer: Timer?
    private var watchdogTimer: Timer?
    private var ramp: BrightnessRamp?
    private var rampStartedAt = Date()
    private var lastWritten: Float = 1.0
    private var restoreLevel: Float = fallbackRestoreLevel
    /// When the current peek window began, or nil while the screen is being held
    /// dark. See `superviseDark()`.
    private var peekStartedAt: Date?
    /// The level the peek window last saw, so a further key press can be told
    /// from the level sitting where it was left.
    private var peekLevel: Float = 0
    /// True between a sleep notification and the matching wake. While set, nothing
    /// touches DisplayServices — that is what used to hang the main thread.
    private var displayAsleep = false
    /// Dusk turned low power mode on during this run, so Dusk may turn it back
    /// off on the way out. A value adopted from the system at launch is the
    /// user's, and quitting must leave it alone.
    private var engagedLowPowerHere = false

    var canDim: Bool { brightness != nil }

    init() {
        restoreLevel = storedRestoreLevel() ?? Self.fallbackRestoreLevel
        observeSleepAndWake()
    }

    // MARK: - Applying state

    /// Moves the system to `target`. Power settings are written one at a time and
    /// off the main thread; the fade starts immediately and runs alongside.
    func apply(_ target: DuskState, completion: @escaping (Result<Void, Error>) -> Void) {
        let screenStep: PowerStep = { [weak self] done in
            self?.setDark(target.dark)
            done(.success(()))
        }
        let powerSteps: [PowerStep] = [
            { [weak self] done in self?.setAwake(target.awake, done: done) },
            { [weak self] done in self?.setLowPower(target.lowPower, done: done) },
        ]

        // Going off, the screen comes back before anything that might raise a
        // dialog. Going on, it goes dark last, for the same reason.
        let steps = target.restoresScreenFirst ? [screenStep] + powerSteps
                                              : powerSteps + [screenStep]

        sequence(steps) { [weak self] result in
            guard let self else { return completion(result) }
            guard case .failure = result else {
                self.syncWakeKeeper()
                self.onChange?()
                return completion(result)
            }

            // A step failed after the earlier ones had already committed, so
            // `state` no longer describes the machine — turning off can leave
            // `dark` false and `awake` true, which keeps the display-sleep
            // assertion held for a switch that is not actually set. Worse, the
            // stale belief makes the next `setAwake`/`setLowPower` short-circuit
            // on its `guard on != state.…` and never retry the write that would
            // put it right. Read the two settings back before reporting.
            PowerCommands.readSystemState { [weak self] awake, lowPower in
                guard let self else { return completion(result) }
                if let awake { self.state.awake = awake }
                if let lowPower { self.state.lowPower = lowPower }
                self.syncWakeKeeper()
                self.onChange?()
                completion(result)
            }
        }
    }

    private func setAwake(_ on: Bool, done: @escaping (Result<Void, Error>) -> Void) {
        guard on != state.awake else { return done(.success(())) }
        PowerCommands.setSleepDisabled(on) { [weak self] result in
            if case .success = result { self?.state.awake = on }
            done(result)
        }
    }

    private func setLowPower(_ on: Bool, done: @escaping (Result<Void, Error>) -> Void) {
        guard on != state.lowPower else { return done(.success(())) }
        PowerCommands.setLowPowerMode(on) { [weak self] result in
            if case .success = result {
                self?.state.lowPower = on
                // Ownership follows the write: Dusk turned it on, so Dusk may
                // turn it off again on quit.
                self?.engagedLowPowerHere = on
            }
            done(result)
        }
    }

    private func syncWakeKeeper() {
        // Held for either switch.
        //
        // `dark` needs it for a mechanical reason: it stops macOS sleeping the
        // panel out from under a backlight Dusk is pinning at zero, which would
        // come back at zero with no event to correct it.
        //
        // `awake` needs it because of what Dusk means. `disablesleep` only blocks
        // *system* sleep; display sleep is a separate timer (`displaysleep`, two
        // minutes on battery) that runs regardless, and the screen going off takes
        // the auto-lock with it. Tying the assertion to `dark` alone meant that
        // turning the dark rider off left Dusk switched on and apparently doing
        // nothing — screen dead and locked inside two minutes — which is both the
        // complaint that found this and the reason a lock screen can never be read
        // as evidence that Dusk was off.
        //
        // Costs nothing in the case Dusk was built for: a closed lid turns the
        // panel off itself, and this assertion does not fight that.
        if state.awake || state.dark { wakeKeeper.prevent() } else { wakeKeeper.allow() }
    }

    // MARK: - Screen

    func setDark(_ on: Bool) {
        guard on != state.dark, let brightness else { return }

        // Only capture while the screen is at rest and bright. If a restore is
        // still in flight, the level it is heading for is the one to keep.
        if on, rampTimer == nil {
            let current = brightness.read() ?? Self.fallbackRestoreLevel
            restoreLevel = current > Self.darkCeiling ? current : Self.fallbackRestoreLevel
        }

        state.dark = on
        endPeek()
        persistRestoreState(dark: on)
        if on {
            startRamp(to: 0, over: Self.dimDuration)
        } else {
            startRamp(to: restoreLevel, over: Self.restoreDuration)
        }
        syncWakeKeeper()
        onChange?()
    }

    private func startRamp(to target: Float, over duration: TimeInterval) {
        stopWatchdog()
        rampTimer?.invalidate()
        guard !displayAsleep else { return }

        // The one point in a fade where the set of attached displays can have
        // changed since the last write.
        brightness?.refreshDisplays()

        let from = brightness?.read() ?? lastWritten
        ramp = BrightnessRamp(from: from, to: target, duration: duration)
        rampStartedAt = Date()
        lastWritten = from

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps the fade running while the menu is open; the default mode
        // stalls for the duration of menu tracking.
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
    }

    private func tick() {
        guard !displayAsleep else { return }
        guard let ramp, let brightness else { return }

        if let actual = brightness.read(), abs(actual - lastWritten) > Self.interventionThreshold {
            abandonRamp(adopting: actual)
            return
        }

        let elapsed = Date().timeIntervalSince(rampStartedAt)
        let value = ramp.value(at: elapsed)
        brightness.write(value)
        lastWritten = value

        guard ramp.isFinished(at: elapsed) else { return }
        stopRamp()
        if state.dark { startWatchdog() }
    }

    private func stopRamp() {
        rampTimer?.invalidate()
        rampTimer = nil
        ramp = nil
    }

    /// Someone reached for the brightness keys mid-fade. Stop fighting them — but
    /// the dark switch stays on, so the supervisor has to take over the moment
    /// the ramp timer lets go.
    private func abandonRamp(adopting level: Float) {
        stopRamp()
        lastWritten = level
        guard state.dark else { return }
        beginPeek(at: level)
        startWatchdog()
    }

    // MARK: - Peek window

    /// Once the screen is black the menu bar is invisible, so the brightness key is
    /// the only thing you can reach without aiming at something you cannot see.
    /// Pressing it buys a look at the screen; Dusk fades it back down afterwards
    /// rather than giving the screen up for good, so switching Dusk off is a
    /// deliberate act rather than a side effect of wanting to see.
    private func startWatchdog() {
        stopWatchdog()
        guard !displayAsleep else { return }
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.superviseDark() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Runs on the watchdog beat for as long as the dark switch is on, in one of
    /// two phases: holding the screen at zero and waiting for a key press, or
    /// inside a peek window and waiting for it to run out.
    private func superviseDark() {
        guard !displayAsleep, state.dark, let actual = brightness?.read() else { return }

        let action = DarkGracePolicy.decide(
            level: actual,
            graceLevel: peekStartedAt == nil ? nil : peekLevel,
            elapsed: peekStartedAt.map { Date().timeIntervalSince($0) } ?? 0,
            delay: Self.peekDuration,
            darkCeiling: Self.darkCeiling,
            threshold: Self.interventionThreshold
        )

        switch action {
        case .hold:
            break
        case .yield:
            beginPeek(at: actual)
        case .redim:
            endPeek()
            // Invalidates this very timer before rearming it on the far side of
            // the fade, which `tick` does once the screen is back at zero.
            startRamp(to: 0, over: Self.dimDuration)
        }
    }

    /// Hand the screen over and start the clock. Called again on every further
    /// adjustment, which is what pushes the deadline back.
    private func beginPeek(at level: Float) {
        peekStartedAt = Date()
        peekLevel = level
        lastWritten = level
        // Switching Dusk off should land on whatever they chose to look at,
        // not on the level from before the screen went dark.
        if level > Self.darkCeiling {
            restoreLevel = level
            persistRestoreState(dark: state.dark)
        }
    }

    private func endPeek() {
        peekStartedAt = nil
    }

    // MARK: - Sleep and wake

    /// The bug this app shipped with: nothing here at all.
    ///
    /// The backlight level is remembered across sleep by macOS, so a machine that
    /// slept at zero woke at zero — a black screen with no way back, because the
    /// escape hatch only fires when the level rises. Meanwhile the 0.4s watchdog
    /// kept calling into DisplayServices across the sleep transition, where those
    /// private calls can block, and a blocked main thread in a menu bar app is the
    /// spinning wheel.
    ///
    /// So: hand the screen back before sleeping, freeze every timer while the
    /// display is gone, and re-dim once it has come back.
    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ names: [NSNotification.Name], with handler: @escaping (DuskController) -> Void) {
            for name in names {
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        handler(self)
                    }
                }
            }
        }

        // Both names in each pair arrive for an ordinary sleep / wake; the second
        // one lands on a guard that has already flipped and does nothing.
        observe([NSWorkspace.willSleepNotification,
                 NSWorkspace.screensDidSleepNotification]) { $0.handleDisplayGoingAway() }
        observe([NSWorkspace.didWakeNotification,
                 NSWorkspace.screensDidWakeNotification]) { $0.handleDisplayComingBack() }
    }

    private func handleDisplayGoingAway() {
        guard !displayAsleep else { return }

        // Stop the timers first: from here on nothing may touch DisplayServices.
        stopRamp()
        stopWatchdog()

        // A peek does not survive the display going away; `handleDisplayComingBack`
        // re-dims from scratch, which is the right place to start over.
        endPeek()

        // One last write, so macOS stores a level the user can see rather than the
        // zero Dusk was holding. The dark switch stays on and is re-applied on wake.
        if state.dark {
            brightness?.write(restoreLevel)
            lastWritten = restoreLevel
        }
        displayAsleep = true
    }

    private func handleDisplayComingBack() {
        guard displayAsleep else { return }
        displayAsleep = false

        guard state.dark else { return }
        // Give the panel a moment to finish coming back before pinning it again;
        // a write that lands mid-wake gets overwritten by the system's own restore.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeSettleDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.dark, !self.displayAsleep else { return }
                self.startRamp(to: 0, over: Self.restoreDuration)
            }
        }
    }

    // MARK: - Crash recovery

    /// `pmset` settings and the backlight level all outlive the process, so a run
    /// that ended without cleanup leaves the Mac unable to sleep and, worse, with
    /// a screen the user cannot turn back on. Called once at launch.
    ///
    /// Reports whether the sudoers rule is in place, which falls out of the same
    /// call that resets `disablesleep` — see PowerCommands for why that is the
    /// only reliable way to ask.
    func recoverFromPreviousRun(completion: @escaping (_ hasPrivilege: Bool) -> Void) {
        // The screen first: a black panel is what the user is stuck looking at,
        // and it needs no privileges to put right.
        if UserDefaults.standard.bool(forKey: Self.wasDarkKey) {
            let level = storedRestoreLevel() ?? Self.fallbackRestoreLevel
            if let current = brightness?.read(), current <= Self.darkCeiling {
                brightness?.write(level)
                lastWritten = level
            }
            persistRestoreState(dark: false)
        }

        PowerCommands.clearSleepDisabledAndCheckPermission { [weak self] granted in
            guard let self else { return completion(granted) }

            // Both settings come from reading the machine, never from assuming
            // the write above worked. When there is no sudoers rule the clear
            // fails, and a previous run that died with `disablesleep 1` leaves
            // the Mac unable to sleep; assuming `false` here painted an idle
            // icon over that and — because `setAwake` short-circuits on
            // `guard on != state.awake` — made every later click a no-op, so
            // nothing could ever issue the corrective write. Reporting the true
            // value instead shows the icon as on, and a click retries the write
            // and surfaces the failure.
            //
            // Low power mode is adopted rather than reset for a different
            // reason: unlike disablesleep it is a setting people turn on for
            // themselves in System Settings, and clearing it at every launch
            // would fight them.
            PowerCommands.readSystemState { [weak self] awake, lowPower in
                guard let self else { return completion(granted) }
                self.state.awake = awake ?? false
                self.state.lowPower = lowPower ?? false
                // Only a low power mode Dusk itself engages may be undone on
                // quit; one adopted here belongs to the user.
                self.engagedLowPowerHere = false
                self.syncWakeKeeper()
                self.onChange?()
                completion(granted)
            }
        }
    }

    /// Best-effort synchronous undo on quit. Runs on the main thread on purpose:
    /// the app is going away and there is no run loop left to deliver callbacks.
    func revertOnTerminate() {
        stopRamp()
        stopWatchdog()
        wakeKeeper.allow()

        if state.dark {
            brightness?.write(restoreLevel)
        }
        persistRestoreState(dark: false)

        // `disablesleep` is cleared unconditionally. Gating it on `state.awake`
        // meant that whenever the belief had drifted from the machine — a write
        // that failed, or a value adopted at launch — quitting left the Mac
        // permanently unable to sleep with no Dusk running to correct it. The
        // write is idempotent, so being wrong costs one round-trip and being
        // right costs nothing.
        PowerCommands.revertSleepDisabledBlocking()

        // Low power mode is only undone when Dusk was the one that set it. It is
        // adopted from the system at launch, so undoing it unconditionally
        // switched off a setting the user had turned on in System Settings.
        if engagedLowPowerHere {
            PowerCommands.revertLowPowerModeBlocking()
        }
    }

    // MARK: - Persistence

    private func storedRestoreLevel() -> Float? {
        guard UserDefaults.standard.object(forKey: Self.restoreLevelKey) != nil else { return nil }
        let value = UserDefaults.standard.float(forKey: Self.restoreLevelKey)
        return value > Self.darkCeiling ? value : nil
    }

    private func persistRestoreState(dark: Bool) {
        UserDefaults.standard.set(dark, forKey: Self.wasDarkKey)
        UserDefaults.standard.set(restoreLevel, forKey: Self.restoreLevelKey)
    }

    // MARK: - Step sequencing

    private typealias PowerStep = (@escaping (Result<Void, Error>) -> Void) -> Void

    /// Runs steps one after another, stopping at the first failure. Power writes
    /// must not overlap: each one is a separate `sudo` round-trip.
    private func sequence(_ steps: [PowerStep], completion: @escaping (Result<Void, Error>) -> Void) {
        var remaining = steps
        func next() {
            guard !remaining.isEmpty else { return completion(.success(())) }
            let step = remaining.removeFirst()
            step { result in
                switch result {
                case .success: next()
                case .failure(let error): completion(.failure(error))
                }
            }
        }
        next()
    }
}
