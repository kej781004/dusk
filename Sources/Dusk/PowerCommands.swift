import Foundation
import DuskCore

enum PowerCommandError: LocalizedError {
    case notPermitted
    case failed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .notPermitted:
            return "sudoers 규칙이 없어 pmset을 실행할 수 없습니다."
        case .failed(let status, let message):
            return message.isEmpty ? "pmset 실패 (종료 코드 \(status))"
                                   : "pmset 실패 (종료 코드 \(status)): \(message)"
        }
    }
}

/// Runs the two `pmset` settings Dusk owns.
///
/// Neither can be set without root: `disablesleep` and `lowpowermode` both live
/// in a root-owned plist, and `IOPMSetValueInt` returns success while silently
/// changing nothing. Dusk relies on a sudoers rule listing exactly four fixed
/// commands — see scripts/install-sudoers.sh.
///
/// Every call runs on a background serial queue. `Process.waitUntilExit()` on
/// the main thread would freeze the menu bar for the length of the round-trip,
/// which is the spinning-wheel bug this app had; the serial queue additionally
/// keeps two writes from racing.
enum PowerCommands {
    private static let queue = DispatchQueue(label: "parkchanbin.Dusk.pmset")

    /// `-n` never prompts — a menu bar app has no terminal to answer on, so a
    /// prompt would hang the call forever.
    ///
    /// `-k` ignores any cached sudo timestamp. Without it, every call quietly
    /// succeeds for a few minutes after the user has typed their password
    /// anywhere else, and then starts failing once that expires — the switch
    /// would work when tested and break later. With `-k` the only thing that can
    /// make these succeed is the NOPASSWD rule, so behaviour never depends on
    /// invisible state. (`-k` in this form ignores the timestamp for this
    /// invocation only; it does not clear the user's.)
    private static let sudoFlags = ["-n", "-k"]

    // MARK: - Reading

    /// Reads both settings back from the system. Runs off the main thread.
    static func readSystemState(completion: @escaping (_ awake: Bool?, _ lowPower: Bool?) -> Void) {
        queue.async {
            let awake = run("/usr/bin/pmset", ["-g"]).stdout
                .flatMap { PowerSettings.parse(sleepDisabled: $0) }
            let lowPower = run("/usr/bin/pmset", ["-g", "custom"]).stdout
                .flatMap { PowerSettings.parse(lowPowerMode: $0) }
            DispatchQueue.main.async { completion(awake, lowPower) }
        }
    }

    /// Clears `disablesleep` and reports whether the sudoers rule is in place.
    ///
    /// These are one call on purpose. There is no way to ask sudo "could I run
    /// this without a password?" — `sudo -l` only reports what the user is
    /// allowed to run at all, which for an admin account is everything, so it
    /// answers yes even with no rule installed. The only honest test is to run
    /// the command and look at the exit status.
    ///
    /// `disablesleep 0` is the right command to test with because Dusk wants to
    /// run it at launch regardless: it is a persistent system setting, so an
    /// instance that was force-killed while active leaves the Mac unable to
    /// sleep, and nothing else on the system would put that back. Setting it to
    /// the value it already has costs nothing.
    ///
    /// Low power mode is deliberately not touched here — people do set that one
    /// themselves in System Settings — and it needs no separate probe, since the
    /// installer grants all four commands together.
    static func clearSleepDisabledAndCheckPermission(completion: @escaping (Bool) -> Void) {
        queue.async {
            let granted = run("/usr/bin/sudo",
                              sudoFlags + ["/usr/bin/pmset", "-a", "disablesleep", "0"]).status == 0
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: - Writing

    static func setSleepDisabled(_ on: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        write("disablesleep", on, completion: completion)
    }

    static func setLowPowerMode(_ on: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        write("lowpowermode", on, completion: completion)
    }

    private static func write(_ setting: String,
                              _ on: Bool,
                              completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = run("/usr/bin/sudo",
                             sudoFlags + ["/usr/bin/pmset", "-a", setting, on ? "1" : "0"])
            DispatchQueue.main.async {
                switch result.status {
                case 0:
                    completion(.success(()))
                case 1 where result.stderr.contains("password is required"):
                    completion(.failure(PowerCommandError.notPermitted))
                default:
                    completion(.failure(PowerCommandError.failed(status: result.status,
                                                                 message: result.stderr)))
                }
            }
        }
    }

    /// Blocking best-effort undo for `applicationWillTerminate`, where there is
    /// no run loop left to deliver an async completion.
    ///
    /// Split in two because the two settings are not owned the same way.
    /// `disablesleep` is Dusk's alone and is always cleared on the way out — the
    /// cost of leaving it set is a Mac that can never sleep again. Low power mode
    /// is a setting people also turn on for themselves, so it is only put back
    /// when Dusk was the one that set it.
    static func revertSleepDisabledBlocking() {
        _ = run("/usr/bin/sudo", sudoFlags + ["/usr/bin/pmset", "-a", "disablesleep", "0"])
    }

    static func revertLowPowerModeBlocking() {
        _ = run("/usr/bin/sudo", sudoFlags + ["/usr/bin/pmset", "-a", "lowpowermode", "0"])
    }

    // MARK: - Process plumbing

    private static func run(_ path: String,
                            _ arguments: [String]) -> (status: Int32, stdout: String?, stderr: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        task.standardInput = FileHandle.nullDevice

        do { try task.run() } catch { return (-1, nil, "\(error)") }

        // Both pipes are drained *concurrently*, then the exit is awaited. A
        // process that fills a pipe nobody is reading blocks forever, and
        // reading them one after the other does not avoid that: draining stdout
        // to EOF blocks until the child closes stdout, so a child that filled
        // stderr in the meantime would deadlock against a reader that has not
        // got to it yet. One of the two has to run on another thread.
        var errData = Data()
        let errDrained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errDrained.signal()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        errDrained.wait()
        task.waitUntilExit()

        return (task.terminationStatus,
                String(data: outData, encoding: .utf8),
                String(data: errData, encoding: .utf8) ?? "")
    }
}
