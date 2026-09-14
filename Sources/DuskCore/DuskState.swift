import Foundation

/// What the three switches are doing right now.
public struct DuskState: Equatable {
    /// `pmset disablesleep` — the only thing that stops a closed lid from
    /// sleeping the Mac. This is the switch Dusk exists for; the other two are
    /// conveniences that ride along with it.
    public var awake: Bool
    public var lowPower: Bool
    public var dark: Bool

    public init(awake: Bool, lowPower: Bool, dark: Bool) {
        self.awake = awake
        self.lowPower = lowPower
        self.dark = dark
    }

    /// Anything at all is engaged. Drives the order the switches move in; the
    /// menu bar icon follows `awake` alone, since low power mode is adopted from
    /// whatever the system was already doing.
    public var isActive: Bool { awake || lowPower || dark }

    /// Which way to move when heading for this state.
    ///
    /// On the way off the screen comes back first, so that any dialog or
    /// notification the other switches raise lands somewhere the user can read
    /// it. On the way on the screen goes dark last, for the same reason.
    public var restoresScreenFirst: Bool { !isActive }
}
