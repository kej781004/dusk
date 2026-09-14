import Foundation

/// Minimal assertion harness. XCTest ships with Xcode, which isn't installed on
/// this Mac, so verification runs as a plain executable instead.
enum Check {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var currentTest = ""

    static func test(_ name: String, _ body: () -> Void) {
        currentTest = name
        let before = failures.count
        body()
        if failures.count == before {
            passed += 1
            print("  ok   \(name)")
        }
    }

    static func fail(_ message: String) {
        failures.append("\(currentTest): \(message)")
        print("  FAIL \(currentTest)")
        print("       \(message)")
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: String = "") {
        if actual != expected {
            fail("\(what.isEmpty ? "" : what + ": ")expected \(expected), got \(actual)")
        }
    }

    static func close(_ actual: Float, _ expected: Float, tol: Float = 1e-5, _ what: String = "") {
        if abs(actual - expected) > tol {
            fail("\(what.isEmpty ? "" : what + ": ")expected \(expected) ±\(tol), got \(actual)")
        }
    }

    static func isTrue(_ cond: Bool, _ what: String) {
        if !cond { fail("expected true: \(what)") }
    }

    static func summarize() -> Never {
        print("")
        if failures.isEmpty {
            print("PASS — \(passed) checks")
            exit(0)
        }
        print("FAIL — \(failures.count) failure(s), \(passed) passed")
        for f in failures { print("  • \(f)") }
        exit(1)
    }
}
