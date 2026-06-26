import Foundation

// v1.141 — shared shrink-phase emitters for the strategist-routed verify
// stubs. The strategist handles Int / fixed-width-integer carriers (Route 2 of
// the verify dispatch); for those the failing counterexample can be minimized
// via swift-property-based's `shrink(towards: 0)`. Non-numeric strategist
// carriers (String / Bool / enums / OC collections / arrays) have no
// `shrink(towards: 0)` and degrade gracefully — the caller emits no shrink
// phase, so the stub reports the first failing input verbatim, exactly as
// before v1.141.
//
// Each helper assumes the surrounding stub's input variable names: `value`
// (single), `lhs`/`rhs` (pair), `valueA`/`valueB`/`valueC` (triple). The
// `oracle` is a Bool expression over `candidate` (single) or
// `aValue`/`bValue`[/`cValue`] (pair/triple) that is `true` when the candidate
// still violates the property.
extension StrategistDispatchEmitter {

    /// Carrier type-names whose values can be shrunk via `shrink(towards: 0)`.
    /// All other strategist carriers degrade gracefully (no shrink phase).
    static let shrinkableScalarCarriers: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64"
    ]

    /// Single-input shrink phase (round-trip, idempotence).
    static func singleShrinkPhase(carrier: String, oracle: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing input ---
                func stillFails(_ candidate: \(carrier)) -> Bool { \(oracle) }
                var shrunk = value
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for part in shrunk.shrink(towards: 0) where stillFails(part) {
                        shrunk = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: \\(shrunk)")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }

    /// Pair-input shrink phase (commutativity): shrink `lhs` then `rhs`.
    static func pairShrinkPhase(carrier: String, oracle: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing pair ---
                func stillFails(_ aValue: \(carrier), _ bValue: \(carrier)) -> Bool { \(oracle) }
                var shrunkLhs = lhs
                var shrunkRhs = rhs
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for part in shrunkLhs.shrink(towards: 0) where stillFails(part, shrunkRhs) {
                        shrunkLhs = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    for part in shrunkRhs.shrink(towards: 0) where stillFails(shrunkLhs, part) {
                        shrunkRhs = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(shrunkLhs), \\(shrunkRhs))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }

    /// Triple-input shrink phase (associativity): shrink A, B, then C.
    static func tripleShrinkPhase(carrier: String, oracle: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing triple ---
                func stillFails(_ aValue: \(carrier), _ bValue: \(carrier), _ cValue: \(carrier)) -> Bool {
                    \(oracle)
                }
                var shrunkA = valueA
                var shrunkB = valueB
                var shrunkC = valueC
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for part in shrunkA.shrink(towards: 0) where stillFails(part, shrunkB, shrunkC) {
                        shrunkA = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    for part in shrunkB.shrink(towards: 0) where stillFails(shrunkA, part, shrunkC) {
                        shrunkB = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    for part in shrunkC.shrink(towards: 0) where stillFails(shrunkA, shrunkB, part) {
                        shrunkC = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(shrunkA), \\(shrunkB), \\(shrunkC))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }
}
