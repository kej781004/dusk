import Foundation
import DuskCore

/// Everything the popover shows, and the calls it makes back to the app.
///
/// An `ObservableObject` rather than view `@State`: the `@State` macro needs a
/// compiler plugin the command-line tools do not ship, so nothing here may
/// lean on it.
public final class PopoverModel: ObservableObject {
    public enum Phase: Equatable {
        case off
        case countingDown(until: Date)
        case indefinite
        case paused
    }

    @Published public var phase: Phase = .off
    /// Where the ruler's needle rests when nobody is dragging it.
    @Published public var restingStop: Int = DurationScale.stop(forMinutes: 15)
    /// The stop under the pointer while the ruler is being dragged.
    @Published public var draggingStop: Int?
    @Published public var lowPower = true
    @Published public var dim = true
    @Published public var canDim = true
    @Published public var threshold = 0
    /// The slider's value while it is being dragged; it commits on release.
    @Published public var draggingThreshold: Int?
    /// What a left click on the icon keeps Dusk on for, shown when off.
    @Published public var clickMinutes = 15
    /// True only while the popover is on screen. Everything that moves is built
    /// only while this is set, so a closed popover costs nothing.
    @Published public var isVisible = false

    public var onCommitStop: (Int) -> Void = { _ in }
    public var onSetLowPower: (Bool) -> Void = { _ in }
    public var onSetDim: (Bool) -> Void = { _ in }
    public var onSetThreshold: (Int) -> Void = { _ in }
    public var onQuit: () -> Void = {}

    public init() {}

    /// Something is keeping the Mac awake right now.
    public var isLive: Bool {
        switch phase {
        case .countingDown, .indefinite: return true
        case .off, .paused: return false
        }
    }

    public var needleStop: Int { draggingStop ?? restingStop }

    /// Faint when the needle only remembers a past choice.
    public var needleIsLive: Bool { draggingStop != nil || isLive }
}
