import IOKit.pwr_mgt

/// Holds an IOPMAssertion that prevents display sleep, screen saver, and
/// auto-lock while Dusk is active. Same mechanism as `caffeinate -d`. Released
/// automatically if the app exits.
///
/// This matters more for Dusk than it did for Awayke: Dusk holds the backlight
/// at zero itself, and if macOS were allowed to sleep the display underneath
/// that, waking it would hand the panel back at whatever level was stored —
/// zero — with no event to tell Dusk to put it right.
final class DisplayWakeKeeper {

    private var assertionID: IOPMAssertionID = 0

    func prevent() {
        guard assertionID == 0 else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Dusk is active" as CFString,
            &assertionID
        )
        if result != kIOReturnSuccess {
            assertionID = 0
        }
    }

    func allow() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
