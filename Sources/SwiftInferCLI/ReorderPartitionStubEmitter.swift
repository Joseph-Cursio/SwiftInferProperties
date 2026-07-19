import Foundation

/// Emits a standalone verifier for the **reorder-partition** law — the
/// measured half of `ReorderPartitionTemplate`.
///
/// Given a `mutating` method that reorders an `[Int]` around a predicate and
/// returns the pivot (`partition(by:) -> Int` / `stablePartition(subrange:by:)
/// -> Int`), the generated `main.swift` drives it over deterministically
/// generated arrays and asserts the law:
///
///  1. **Two-sided split** — everything before the pivot fails the predicate,
///     everything at/after satisfies it.
///  2. **Permutation** — the result is a rearrangement of the input (multiset
///     preserved), which for the *stable* form strengthens to the elements of
///     each side equalling the order-preserving filter of the original.
///  3. **Subrange fence** — a subrange variant moves only the elements inside
///     the subrange and lands the pivot inside it; everything outside is
///     untouched (the exact swift-algorithms `0dba0e5` failure mode).
///
/// The carrier is `[Int]` with a small alphabet (`0..<5`) so duplicates appear
/// — a partition that drops or duplicates an element is caught by (2). The
/// corpus method is co-compiled into the verifier target (direct source
/// inclusion), so the stub calls it in-module — no import beyond `Foundation`
/// plus any `extraImports`. Emits the same `VERIFY_*` marker contract as the
/// algebraic / ViewModel stubs (`exit(1)` on FAIL) so `VerifyResultParser`
/// consumes it unchanged.
///
/// **Scope (this slice):** an `[Int]` carrier + a `{ $0 >= threshold }`
/// predicate — the value-semantic shape swift-algorithms' own partition tests
/// use. A generic element type would delegate to `DerivationStrategist` (PRD
/// §11); the `[Int]` literal keeps the verifier dependency-free.
public enum ReorderPartitionStubEmitter {

    public struct Inputs: Equatable, Sendable {
        /// The mutating method on `[Int]` to verify.
        public let methodName: String
        /// `true` when the method takes a leading `subrange:` argument and must
        /// respect the fence.
        public let hasSubrange: Bool
        /// `true` when the name promises stability — only then is the stronger
        /// order-preserving check asserted.
        public let isStable: Bool
        /// Trials per run (deterministic; a fixed seed makes this reproducible).
        public let trials: Int
        /// Modules to import beyond `Foundation` — e.g. a path-dependency
        /// package the carrier extension lives in.
        public let extraImports: [String]

        public init(
            methodName: String,
            hasSubrange: Bool,
            isStable: Bool,
            trials: Int = 2_000,
            extraImports: [String] = []
        ) {
            self.methodName = methodName
            self.hasSubrange = hasSubrange
            self.isStable = isStable
            self.trials = trials
            self.extraImports = extraImports
        }
    }

    public static func emit(_ inputs: Inputs) -> String {
        let imports = (["Foundation"] + inputs.extraImports)
            .map { "import \($0)" }
            .joined(separator: "\n")
        return """
        // Auto-generated reorder-partition verifier.
        // Method: [Int].\(inputs.methodName)\(inputs.hasSubrange ? "(subrange:by:)" : "(by:)")
        \(imports)

        \(rngDefinition)

        func runReorderPartitionCheck() -> (pass: Bool, detail: String) {
            var rng = StubXoshiro(seed: 0xA5A5_5A5A_C3C3_3C3C)
            let threshold = 3
            let pred: (Int) -> Bool = { $0 >= threshold }
            for _ in 0..<\(inputs.trials) {
                let count = Int(rng.next() % 13)
                let original: [Int] = (0..<count).map { _ in Int(rng.next() % 5) }
                var arr = original
        \(bodyBlock(inputs))
            }
            return (true, "")
        }

        let outcome = runReorderPartitionCheck()
        if outcome.pass {
            print("VERIFY_DEFAULT_RESULT: PASS")
            print("VERIFY_DEFAULT_TRIALS: \(inputs.trials)")
            print("VERIFY_EDGE_RESULT: PASS")
            print("VERIFY_EDGE_TRIALS: 0")
            print("VERIFY_EDGE_SAMPLED: 0")
            exit(0)
        } else {
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            print("VERIFY_DEFAULT_DETAIL: \\(outcome.detail)")
            exit(1)
        }
        """
    }

    // MARK: - Body

    private static func bodyBlock(_ inputs: Inputs) -> String {
        inputs.hasSubrange ? subrangeBody(inputs) : wholeBody(inputs)
    }

    private static func wholeBody(_ inputs: Inputs) -> String {
        """
                let pivot = arr.\(inputs.methodName)(by: pred)
                guard pivot >= 0, pivot <= arr.count else {
                    return (false, "pivot out of range: pivot=\\(pivot) count=\\(arr.count)")
                }
        \(wholeChecks(inputs))
        """
    }

    private static func wholeChecks(_ inputs: Inputs) -> String {
        if inputs.isStable {
            return """
                    if Array(arr[..<pivot]) != original.filter({ !pred($0) })
                        || Array(arr[pivot...]) != original.filter({ pred($0) }) {
                        return (false, "stable law violated: in=\\(original) out=\\(arr) pivot=\\(pivot)")
                    }
            """
        }
        return """
                let before = Array(arr[..<pivot])
                let after = Array(arr[pivot...])
                if !before.allSatisfy({ !pred($0) }) || !after.allSatisfy({ pred($0) }) {
                    return (false, "split violated: in=\\(original) out=\\(arr) pivot=\\(pivot)")
                }
                if arr.sorted() != original.sorted() {
                    return (false, "permutation violated: in=\\(original) out=\\(arr)")
                }
        """
    }

    private static func subrangeBody(_ inputs: Inputs) -> String {
        """
                let bound1 = count == 0 ? 0 : Int(rng.next() % UInt64(count + 1))
                let bound2 = count == 0 ? 0 : Int(rng.next() % UInt64(count + 1))
                let subrange = Swift.min(bound1, bound2)..<Swift.max(bound1, bound2)
                let pivot = arr.\(inputs.methodName)(subrange: subrange, by: pred)
                guard arr.count == original.count else {
                    return (false, "count changed: in=\\(original) out=\\(arr)")
                }
                guard pivot >= subrange.lowerBound, pivot <= subrange.upperBound else {
                    return (false, "pivot outside subrange: pivot=\\(pivot) subrange=\\(subrange)")
                }
                if Array(arr[..<subrange.lowerBound]) != Array(original[..<subrange.lowerBound])
                    || Array(arr[subrange.upperBound...]) != Array(original[subrange.upperBound...]) {
                    return (false, "fence violated: in=\\(original) out=\\(arr) subrange=\\(subrange)")
                }
                let subOriginal = Array(original[subrange])
        \(subrangeChecks(inputs))
        """
    }

    private static func subrangeChecks(_ inputs: Inputs) -> String {
        if inputs.isStable {
            return """
                    if Array(arr[subrange.lowerBound..<pivot]) != subOriginal.filter({ !pred($0) })
                        || Array(arr[pivot..<subrange.upperBound]) != subOriginal.filter({ pred($0) }) {
                        return (false, "subrange stable law violated: in=\\(original) out=\\(arr) pivot=\\(pivot)")
                    }
            """
        }
        return """
                let before = Array(arr[subrange.lowerBound..<pivot])
                let after = Array(arr[pivot..<subrange.upperBound])
                if !before.allSatisfy({ !pred($0) }) || !after.allSatisfy({ pred($0) }) {
                    return (false, "subrange split violated: in=\\(original) out=\\(arr) pivot=\\(pivot)")
                }
                if Array(arr[subrange]).sorted() != subOriginal.sorted() {
                    return (false, "subrange permutation violated: in=\\(original) out=\\(arr)")
                }
        """
    }

    /// A small splitmix-seeded xoshiro256** — deterministic so a run is
    /// byte-reproducible (the measured path's determinism guarantee, cycle 118).
    private static let rngDefinition = """
    struct StubXoshiro: RandomNumberGenerator {
        var state: (UInt64, UInt64, UInt64, UInt64)
        init(seed: UInt64) {
            var s = seed
            func splitmix() -> UInt64 {
                s = s &+ 0x9E37_79B9_7F4A_7C15
                var z = s
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
            state = (splitmix(), splitmix(), splitmix(), splitmix())
        }
        mutating func next() -> UInt64 {
            let result = state.0 &+ state.3
            let rotated = state.1 << 17
            state.2 ^= state.0
            state.3 ^= state.1
            state.1 ^= state.2
            state.0 ^= state.3
            state.2 ^= rotated
            state.3 = (state.3 << 45) | (state.3 >> 19)
            return result
        }
    }
    """
}
