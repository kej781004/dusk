import AppKit
import UserNotifications
import DuskCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = DuskController()
    private let batteryMonitor = BatteryMonitor()
    private let autoOffTimer = AutoOffTimer()
    private var statusItem: NSStatusItem!

    private let thresholdDefaultsKey = "autoOffThreshold"
    private let lowPowerPreferenceKey = "engageLowPower"
    private let darkPreferenceKey = "engageDark"
    private let durationOptions = [15, 30, 60, 120]
    /// How long a left click keeps Dusk on.
    private let clickTimerMinutes = 20
    /// Time given to DuskController's 0.8s restore fade before the Mac is put
    /// to sleep at the end of a countdown.
    private static let sleepSettleDelay: TimeInterval = 1.0

    /// The user's intent: do they want Dusk on?
    private var intent = false {
        didSet {
            guard intent != oldValue else { return }
            if intent {
                beginNapExemption()
                startBatteryRecheck()
            } else {
                endNapExemption()
                stopBatteryRecheck()
            }
            Log.power.notice("intent -> \(self.intent, privacy: .public)")
        }
    }
    /// Token from `beginActivity`, held while `intent` is true. See
    /// `beginNapExemption()`.
    private var napActivityToken: NSObjectProtocol?
    /// Re-runs the battery policy on a fixed beat while the user wants Dusk on.
    /// See `startBatteryRecheck()` for why the IOKit notifications alone are not
    /// enough to rely on.
    private var batteryRecheckTimer: Timer?
    /// Battery auto-off is currently holding Dusk off.
    private var suspendedForBattery = false
    /// The user turned Dusk on while already below the floor. Auto-off stands
    /// down until the machine next reaches AC.
    private var overrideBattery = false
    /// Most recent battery reading, for re-evaluating on threshold change.
    private var lastSnapshot: BatterySnapshot?
    /// A pmset round-trip is outstanding. Guards against overlapping calls.
    private var changeInFlight = false
    /// Set once the sudoers rule has been confirmed, so the prompt appears once.
    private var hasPrivilege = false
    /// The menu while it is on screen, so a switch can close it before doing
    /// anything that might need a modal.
    private weak var activeMenu: NSMenu?

    /// Low-battery floor; 0 disables the feature. Persisted.
    private var threshold: Int {
        get { UserDefaults.standard.integer(forKey: thresholdDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: thresholdDefaultsKey) }
    }

    // The two riders are settings, not switches. They say what turning Dusk on
    // should bring with it — flipping one never turns Dusk on or off, and only a
    // left click on the menu bar icon does that.

    /// Engage `pmset lowpowermode` along with Dusk. Persisted.
    private var engagesLowPower: Bool {
        get { UserDefaults.standard.bool(forKey: lowPowerPreferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: lowPowerPreferenceKey) }
    }

    /// Fade the screen out along with Dusk. Persisted.
    private var engagesDark: Bool {
        get { UserDefaults.standard.bool(forKey: darkPreferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: darkPreferenceKey) }
    }

    /// Everything off. The only state a left-click "off" can produce.
    private static let restedState = DuskState(awake: false, lowPower: false, dark: false)

    /// What "on" means right now: the lid switch Dusk exists for, plus whichever
    /// riders are currently switched on in the menu.
    private var engagedState: DuskState {
        DuskState(awake: true, lowPower: engagesLowPower, dark: engagesDark)
    }

    /// What is actually applied to the system.
    private var effectiveActive: Bool { intent && !suspendedForBattery }

    // MARK: - App Nap

    /// Dusk is an LSUIElement with no window, so macOS App Naps it like any other
    /// idle background process — throttling its timers and run-loop delivery. That
    /// includes the battery watchdog, which is exactly the thing that must keep
    /// firing while the lid is closed and nobody is looking. Holding this activity
    /// for as long as the user wants Dusk on opts the process out of napping.
    ///
    /// `.userInitiatedAllowingIdleSystemSleep`, not `.userInitiated`: the plain one
    /// also takes out a PreventUserIdleSystemSleep assertion, which would keep the
    /// Mac awake even after the low-battery auto-off had switched Dusk off —
    /// `intent` stays true across a suspension, so the token stays held, and the
    /// one feature whose entire job is to stop draining the battery would have gone
    /// on draining it. Dusk holds the Mac awake with `pmset` or not at all; this
    /// token exists only to keep the process out of App Nap.
    private func beginNapExemption() {
        napActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Dusk must keep watching the battery while switched on"
        )
    }

    private func endNapExemption() {
        guard let token = napActivityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        napActivityToken = nil
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Both riders start on, which is what a fresh Dusk did before they became
        // settings. `bool(forKey:)` answers false for a key that was never written,
        // so the default has to be registered rather than assumed.
        UserDefaults.standard.register(defaults: [
            lowPowerPreferenceKey: true,
            darkPreferenceKey: true,
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        controller.onChange = { [weak self] in self?.refreshStatusItem() }
        refreshStatusItem()

        // Recovery from crash / force-kill: pmset settings and the backlight level
        // are all persistent, so a previous instance that died without cleanup can
        // leave the Mac unable to sleep behind a screen that will not come back.
        // The same call reports whether the sudoers rule is installed.
        controller.recoverFromPreviousRun { [weak self] granted in
            guard let self else { return }
            self.hasPrivilege = granted
            // Only the lid switch says whether Dusk is on. Low power mode is
            // adopted from the system at launch, and a Mac that had it on in
            // System Settings must not come up looking like Dusk is running.
            self.intent = self.controller.state.awake
            self.refreshStatusItem()
        }

        if threshold > 0 {
            requestNotificationAuthorization()
        }

        batteryMonitor.onChange = { [weak self] snapshot in self?.handleBattery(snapshot) }
        batteryMonitor.start()

        autoOffTimer.onExpire = { [weak self] in self?.handleTimerExpired() }
        // Keeps the tooltip's remaining-time readout live.
        autoOffTimer.onTick = { [weak self] in self?.refreshStatusItem() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Mac unable to sleep, or the screen at zero with nothing
        // running that could bring it back.
        controller.revertOnTerminate()
    }

    // MARK: - Clicks

    /// Left click is the only thing that turns Dusk on or off; right click (a
    /// two-finger click on the trackpad) opens the menu, where the riders are
    /// settings that say what "on" should bring with it.
    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if wantsMenu {
            showMenu()
        } else if effectiveActive {
            setIntent(false)
        } else {
            // A left click turns on in timer mode, the same countdown the
            // "이만큼 켜두기" presets run. "계속" in the menu is still there for
            // an indefinite on.
            setIntent(true, timerMinutes: clickTimerMinutes)
        }
    }

    // MARK: - State application

    /// Manual on/off. Always clears any battery suspension — the user overrides
    /// the auto-off machine.
    ///
    /// - Parameter timerMinutes: arms the auto-off countdown for this many
    ///   minutes. Nil cancels any running countdown (plain on/off is indefinite).
    private func setIntent(_ on: Bool, timerMinutes: Int? = nil) {
        // A click that lands mid-round-trip is dropped: the writes must not
        // overlap, and there is nothing on screen that could show a pending
        // state. Logged rather than silent, because from the outside this is
        // indistinguishable from the icon being dead — which is what sends
        // people clicking again.
        guard !changeInFlight else {
            Log.power.notice("click ignored, write in flight")
            return
        }

        // Turning on needs root for both pmset settings. Ask once, up front,
        // rather than letting the first write fail.
        if on, !hasPrivilege {
            withPrivilege { [weak self] in self?.setIntent(on, timerMinutes: timerMinutes) }
            return
        }

        changeInFlight = true
        let target = on ? engagedState : Self.restedState

        controller.apply(target) { [weak self] result in
            guard let self else { return }
            self.changeInFlight = false
            switch result {
            case .success:
                self.intent = on
                self.suspendedForBattery = false
                // Only an "on" issued while already below the floor counts as an
                // override. Turning on at a healthy charge leaves auto-off armed.
                self.overrideBattery = on && self.isBelowFloor
                if on, let minutes = timerMinutes {
                    self.startCountdown(minutes: minutes)
                } else {
                    self.autoOffTimer.cancel()
                }
                self.refreshStatusItem()
            case .failure(let error):
                self.presentError(error)
            }
        }
    }

    /// Arms the countdown.
    ///
    /// Notification permission is asked here rather than at the click that leads
    /// here, so that it is asked exactly when a countdown really starts: after
    /// any privilege prompt has been answered, and never for a click that failed
    /// to turn Dusk on. Asking at click time put the system permission dialog on
    /// screen at the same moment as the modal sudoers alert on a fresh install.
    private func startCountdown(minutes: Int) {
        requestNotificationAuthorization()
        autoOffTimer.start(minutes: minutes)
    }

    /// Latest reading is on battery and under the configured floor.
    private var isBelowFloor: Bool {
        guard let snapshot = lastSnapshot else { return false }
        return AutoOffPolicy.isBelowFloor(percent: snapshot.percent,
                                          onAC: snapshot.onAC,
                                          threshold: threshold)
    }

    /// The countdown ran out. Same end state as a manual off.
    ///
    /// Called again on every tick until it succeeds. `AutoOffTimer` keeps the
    /// deadline armed past expiry precisely so that this can bail out and be
    /// tried again: turning Dusk off is a `pmset` round-trip, and a countdown
    /// that cancelled itself before the round-trip came back left the Mac unable
    /// to sleep with nothing scheduled to fix it. Only `finishTimerOff` cancels.
    private func handleTimerExpired() {
        // Dusk is already off (a manual click got there first). Nothing to do
        // but stop counting.
        guard intent else {
            autoOffTimer.cancel()
            return
        }

        // Battery auto-off already turned everything off, so there is nothing to
        // undo at the system level — just clear the state.
        guard !suspendedForBattery else {
            finishTimerOff()
            return
        }

        // Another write is mid-flight. The countdown stays armed, so the next
        // tick tries again.
        guard !changeInFlight else {
            Log.power.notice("timer expiry deferred, write in flight")
            return
        }
        changeInFlight = true

        controller.apply(Self.restedState) { [weak self] result in
            guard let self else { return }
            self.changeInFlight = false

            if case .failure(let error) = result {
                // Deliberately not a modal: the countdown is the feature people
                // use with the lid shut, and nobody can dismiss a dialog there.
                // Leaving the deadline armed means the next tick retries — this
                // used to return silently with the countdown already cancelled,
                // which is how the screen came back looking like Dusk had turned
                // off while `disablesleep` was still 1.
                Log.power.error("""
                    timer off failed, will retry: \
                    \(error.localizedDescription, privacy: .public)
                    """)
                return
            }
            self.finishTimerOff()
        }
    }

    /// The bookkeeping both timer-expiry paths end with. `suspendedForBattery` is
    /// already false on the path that went through `controller.apply`; clearing it
    /// unconditionally keeps the two endings from drifting apart.
    ///
    /// This is the only place the countdown is cancelled, so it is cancelled
    /// exactly when the machine has actually been put back.
    private func finishTimerOff() {
        autoOffTimer.cancel()
        intent = false
        suspendedForBattery = false
        overrideBattery = false
        refreshStatusItem()
        notify(title: "Dusk가 꺼졌습니다", body: "타이머가 끝났습니다.")
        sleepAfterCountdown()
    }

    /// A countdown means "hold the Mac up until this is done", so the end of one
    /// puts the Mac to sleep rather than leaving it idling until some other
    /// timeout catches it. Only the countdown ends this way: a manual off and
    /// the low-battery auto-off both leave the machine as they found it — the
    /// battery one especially, since it fires on a Mac whose lid may well be
    /// open.
    ///
    /// The wait is for the screen, not for pmset. Turning off starts the 0.8s
    /// restore fade and `apply` returns before it lands, so sleeping straight
    /// away would freeze the backlight part-way down — and macOS restores
    /// whatever level it slept at, which is the dim-screen-on-wake trap the
    /// sleep handling in DuskController exists to avoid.
    private func sleepAfterCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sleepSettleDelay) {
            PowerCommands.sleepNow()
        }
    }

    /// Re-runs the battery policy on a fixed beat for as long as the user wants
    /// Dusk on.
    ///
    /// `handleBattery` used to be driven by `BatteryMonitor` alone, and that is
    /// not a sound thing to depend on. IOKit reports power *changes*, so a Mac
    /// sitting at 100% on the charger stops producing them entirely — and both
    /// exits out of `handleBattery` (a reading dropped because a pmset write was
    /// still in flight, and a write that came back a failure) leave the decision
    /// unmade with nothing scheduled to make it again. One missed resume then
    /// stands until the charge next moves, which on a full battery can be never:
    /// Dusk stays suspended, the Mac sleeps and locks itself, and no trace of why
    /// is left behind.
    ///
    /// A minute is far below any rate the battery can actually move at, and the
    /// pass costs one IOKit read when nothing needs doing.
    private func startBatteryRecheck() {
        stopBatteryRecheck()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot = self.batteryMonitor.currentSnapshot() else { return }
                self.handleBattery(snapshot)
            }
        }
        // Common modes, so the beat survives the menu being held open.
        RunLoop.main.add(timer, forMode: .common)
        batteryRecheckTimer = timer
    }

    private func stopBatteryRecheck() {
        batteryRecheckTimer?.invalidate()
        batteryRecheckTimer = nil
    }

    private func handleBattery(_ snapshot: BatterySnapshot) {
        lastSnapshot = snapshot
        overrideBattery = AutoOffPolicy.shouldKeepOverride(overrideBattery, onAC: snapshot.onAC)

        let action = AutoOffPolicy.decide(
            intent: intent,
            suspended: suspendedForBattery,
            overridden: overrideBattery,
            percent: snapshot.percent,
            onAC: snapshot.onAC,
            threshold: threshold
        )
        guard action != .none else { return }

        // Power notifications arrive faster than a pmset round-trip completes.
        // Dropping this one is safe now that the recheck timer comes back around;
        // it used to be the start of a permanent stall.
        guard !changeInFlight else {
            Log.battery.notice("action deferred, write in flight")
            return
        }
        changeInFlight = true

        let suspending = (action == .suspend)
        let verb = suspending ? "suspend" : "resume"
        Log.battery.notice("""
            \(verb, privacy: .public) at \
            \(snapshot.percent, privacy: .public)% \
            \(snapshot.onAC ? "AC" : "batt", privacy: .public) \
            floor \(self.threshold, privacy: .public)%
            """)

        // Resuming brings back whatever the riders currently say, not whatever was
        // running when the battery ran down.
        controller.apply(suspending ? Self.restedState : engagedState) { [weak self] result in
            guard let self else { return }
            self.changeInFlight = false

            if case .failure(let error) = result {
                // Deliberately not fatal and deliberately not a modal: this runs
                // with the lid shut and nobody to dismiss a dialog. Leaving
                // `suspendedForBattery` untouched means the next recheck sees the
                // same unmade decision and tries the write again.
                Log.battery.error("""
                    \(verb, privacy: .public) failed, \
                    will retry: \(error.localizedDescription, privacy: .public)
                    """)
                return
            }

            self.suspendedForBattery = suspending
            self.refreshStatusItem()
            if suspending {
                self.notify(title: "Dusk가 꺼졌습니다",
                            body: "배터리가 \(self.threshold)% 아래로 떨어졌습니다.")
            } else {
                self.notify(title: "Dusk가 다시 켜졌습니다",
                            body: "충전 중 — 잠자기 방지를 재개합니다.")
            }

            // State moved on; re-check against anything that arrived while we were
            // waiting. Terminates because each pass flips `suspendedForBattery`.
            if let latest = self.lastSnapshot {
                self.handleBattery(latest)
            }
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()

        let stateTitle: String
        if suspendedForBattery {
            stateTitle = "일시정지 (배터리 부족)"
        } else if !effectiveActive {
            stateTitle = "꺼짐"
        } else if let remaining = autoOffTimer.remaining {
            stateTitle = "켜짐 — \(formatRemaining(remaining)) 남음"
        } else {
            stateTitle = "켜짐"
        }
        let stateItem = NSMenuItem(title: "Dusk: \(stateTitle)", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(.separator())
        menu.addItem(keepAwakeSubmenuItem())
        menu.addItem(autoOffSubmenuItem())

        // The lid switch has no row of its own: not sleeping on a closed lid is
        // what the app is, so it follows the icon rather than being a setting
        // alongside the two that ride with it. These two are settings — they say
        // what a left click should engage, and flipping one is not a left click.
        menu.addItem(.separator())
        menu.addItem(SwitchMenuItemView.item(title: "저전력 모드",
                                             isOn: engagesLowPower,
                                             isEnabled: true) { [weak self] on in
            self?.setPreference { $0.engagesLowPower = on }
        })
        menu.addItem(SwitchMenuItemView.item(title: "화면 어둡게",
                                             isOn: engagesDark,
                                             isEnabled: controller.canDim) { [weak self] on in
            self?.setPreference { $0.engagesDark = on }
        })

        menu.addItem(.separator())
        // The only top-level item carrying an action: the submenu rows set their
        // own target, and the switch rows are view items with no action at all.
        let quitItem = NSMenuItem(title: "Dusk 종료", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // A status item only pops its menu when one is attached, so attach it for
        // the click and detach it afterwards to keep left clicks going to the action.
        activeMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        activeMenu = nil
    }

    private func keepAwakeSubmenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "이만큼 켜두기", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for value in durationOptions {
            let item = NSMenuItem(title: durationLabel(value),
                                  action: #selector(menuKeepAwakeFor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        // Tag 0 means "no countdown" — on until turned off.
        let indefinite = NSMenuItem(title: "계속",
                                    action: #selector(menuKeepAwakeFor(_:)), keyEquivalent: "")
        indefinite.target = self
        indefinite.tag = 0
        indefinite.state = (effectiveActive && !autoOffTimer.isRunning) ? .on : .off
        submenu.addItem(indefinite)

        parent.submenu = submenu
        return parent
    }

    private func autoOffSubmenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "배터리 낮으면 자동 끄기", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        // The submenu holds nothing but the slider, which reports only when the
        // drag ends — a threshold committed on every step would re-evaluate the
        // battery, and a pmset round-trip per pixel of travel.
        submenu.addItem(ThresholdSliderView.item(value: threshold) { [weak self] value in
            self?.setThreshold(value)
        })
        parent.submenu = submenu
        return parent
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    /// Rounded up to the next whole minute, so a live countdown never reads "0분"
    /// while Dusk is still on.
    private func formatRemaining(_ seconds: TimeInterval) -> String {
        durationLabel(max(1, Int((seconds / 60).rounded(.up))))
    }

    // MARK: - Menu actions

    @objc private func menuKeepAwakeFor(_ sender: NSMenuItem) {
        let minutes = sender.tag

        // Already on: just (re)arm the countdown, skipping a pmset round-trip that
        // would set a state the system is already in.
        guard effectiveActive else {
            setIntent(true, timerMinutes: minutes > 0 ? minutes : nil)
            return
        }

        if minutes > 0 {
            startCountdown(minutes: minutes)
        } else {
            autoOffTimer.cancel()
        }
        refreshStatusItem()
    }

    private func setThreshold(_ value: Int) {
        guard value != threshold else { return }
        threshold = value
        if value > 0 { requestNotificationAuthorization() }
        // Re-evaluate against the latest reading so a newly-set threshold that is
        // already breached suspends immediately.
        if let snapshot = lastSnapshot {
            handleBattery(snapshot)
        }
    }

    /// A rider was flipped. It is a setting, so it is written straight away and
    /// `intent` is never touched: no flip of these can turn Dusk on or off.
    ///
    /// If Dusk is already running the change also lands on the machine now, which
    /// is what the switch moving under the pointer promises. The menu closes first
    /// and the work happens on the next pass of the run loop — applying it inline
    /// would run inside menu tracking, where a modal (the privilege prompt, or an
    /// error from a failed `pmset`) has no reliable way to come up.
    private func setPreference(_ change: (AppDelegate) -> Void) {
        change(self)

        guard effectiveActive else { return }
        let target = engagedState
        guard target != controller.state else { return }

        activeMenu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            self?.applyRiders(target)
        }
    }

    /// Brings the machine in line with the riders while Dusk stays on. Unlike a
    /// left click this touches nothing else — not `intent`, not the battery
    /// suspension, not the countdown.
    private func applyRiders(_ target: DuskState) {
        guard !changeInFlight else { return }

        let needsRoot = target.lowPower && !controller.state.lowPower
        if needsRoot, !hasPrivilege {
            withPrivilege { [weak self] in self?.applyRiders(target) }
            return
        }

        changeInFlight = true
        controller.apply(target) { [weak self] result in
            guard let self else { return }
            self.changeInFlight = false
            if case .failure(let error) = result { self.presentError(error) }
            self.refreshStatusItem()
        }
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Privilege

    /// Runs `work` once the sudoers rule is in place, prompting for it first if it
    /// is not. A refused or failed prompt drops `work` — the caller is expected to
    /// be an action the user can simply repeat.
    private func withPrivilege(_ work: @escaping () -> Void) {
        guard !hasPrivilege else { return work() }
        offerPrivilegeSetup { [weak self] granted in
            guard let self, granted else { return }
            self.hasPrivilege = true
            work()
        }
    }

    private func offerPrivilegeSetup(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Dusk를 쓰려면 한 번만 권한이 필요합니다"
        alert.informativeText = """
        뚜껑을 닫아도 안 자게 하려면 `pmset disablesleep`을, 저전력 모드에는 \
        `pmset lowpowermode`를 써야 하는데 둘 다 관리자만 바꿀 수 있습니다.

        아래 버튼을 누르면 암호를 한 번 물어보고, 그 네 명령만 허용하는 규칙을 \
        설치합니다. 그 뒤로는 암호 없이 바로 켜고 꺼집니다.
        """
        alert.addButton(withTitle: "설정하기")
        alert.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(false)
            return
        }
        installPrivilege(completion: completion)
    }

    private func installPrivilege(completion: @escaping (Bool) -> Void) {
        guard let script = Bundle.main.path(forResource: "install-sudoers", ofType: "sh") else {
            present(title: "설치 스크립트를 찾지 못했습니다",
                    body: "앱 번들 안에 install-sudoers.sh가 없습니다.")
            completion(false)
            return
        }

        let quoted = script.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"/bin/sh \\\"\(quoted)\\\"\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)

        if let error {
            // -128 is the user cancelling the password prompt; that needs no alert.
            if (error["NSAppleScriptErrorNumber"] as? Int) != -128 {
                present(title: "권한 설치에 실패했습니다",
                        body: error["NSAppleScriptErrorMessage"] as? String ?? "\(error)")
            }
            completion(false)
            return
        }

        // Confirms by running one of the granted commands, not by asking sudo what
        // is permitted — see PowerCommands for why that question has no useful answer.
        PowerCommands.clearSleepDisabledAndCheckPermission { [weak self] granted in
            if !granted {
                self?.present(title: "규칙이 아직 적용되지 않았습니다",
                              body: "터미널에서 `sudo sh \(script)`를 직접 실행해 보세요.")
            }
            completion(granted)
        }
    }

    // MARK: - Notifications

    /// UNUserNotificationCenter traps when the process has no bundle identity, so
    /// running the binary straight out of .build must not go near it.
    private let canNotify = Bundle.main.bundleIdentifier != nil

    private func requestNotificationAuthorization() {
        guard canNotify else {
            Log.notify.error("no bundle identity; notifications unavailable")
            return
        }
        // The result used to be thrown away, which is how Dusk ended up never
        // appearing in System Settings › Notifications without anyone noticing:
        // the auto-off fired and the one message saying so went nowhere.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.notify.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                Log.notify.notice("authorization granted=\(granted, privacy: .public)")
            }
        }
    }

    private func notify(title: String, body: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Status item rendering

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let state = controller.state
        // The lid switch alone, not `isActive`: low power mode is adopted from the
        // system, so a Mac that had it on before Dusk launched would otherwise
        // show an orange icon for something Dusk never did.
        button.image = StatusIcon.image(active: state.awake, timer: autoOffTimer.isRunning)

        if suspendedForBattery {
            button.toolTip = "Dusk 일시정지 — 배터리가 \(threshold)% 아래입니다. 충전하면 재개합니다."
        } else if state.awake, let remaining = autoOffTimer.remaining {
            button.toolTip = "Dusk 켜짐 — \(formatRemaining(remaining)) 뒤에 꺼집니다."
        } else if state.awake {
            button.toolTip = "Dusk 켜짐 — 뚜껑을 닫아도 안 잡니다."
        } else {
            button.toolTip = "Dusk 꺼짐. 누르면 \(clickTimerMinutes)분 동안 켜집니다."
        }
    }

    private func presentError(_ error: Error) {
        present(title: "Dusk가 설정을 바꾸지 못했습니다", body: error.localizedDescription)
    }

    private func present(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
