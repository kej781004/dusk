import Foundation
import CoreGraphics

/// Reads and writes display backlight level.
///
/// The public API for this is Xcode-only (and gated); DisplayServices is the
/// framework the brightness keys themselves go through, so it is what actually
/// works on Apple silicon internal panels. It is private, hence the dlopen —
/// if Apple ever moves it, `init?` fails and Dusk disables the dark switch
/// rather than crashing.
final class DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn
    private let setFn: SetFn

    init?() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSym = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }

        getFn = unsafeBitCast(getSym, to: GetFn.self)
        setFn = unsafeBitCast(setSym, to: SetFn.self)
    }

    /// Current level of the main display, 0...1.
    func read() -> Float? {
        var value: Float = 0
        guard getFn(CGMainDisplayID(), &value) == 0 else { return nil }
        return value
    }

    /// The displays `write` fans out to, re-read by `refreshDisplays()`.
    ///
    /// Cached because `write` is called once per frame for the length of a ramp:
    /// re-deriving this list 180 times during a three-second fade means 360
    /// round-trips into the window server on the main thread to answer a
    /// question whose answer does not change mid-fade.
    private lazy var displays: [CGDirectDisplayID] = activeDisplays()

    /// Re-reads the attached displays. Called when a ramp starts, which is the
    /// point at which a monitor may have come or gone since the last one.
    func refreshDisplays() {
        displays = activeDisplays()
    }

    /// Writes every attached display. External monitors usually refuse — they
    /// need DDC rather than DisplayServices — so failures are ignored and the
    /// built-in panel still responds.
    func write(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        for display in displays {
            _ = setFn(display, clamped)
        }
    }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return [CGMainDisplayID()]
        }
        return Array(ids.prefix(Int(count)))
    }
}
