import Foundation

/// Emits a standalone verifier for the **codable-round-trip** law — the measured
/// half of `CodableRoundTripTemplate`.
///
/// Given a type `T` with a hand-written `Codable` conformance, the generated
/// `main.swift` drives `JSONDecoder().decode(T.self, from: JSONEncoder()
/// .encode(x)) == x` over deterministically generated values and reports the
/// standard `VERIFY_*` markers (`exit(1)` on FAIL), so `VerifyResultParser`
/// consumes it unchanged. A faithful codec `bothPass`es; a lossy / buggy one (the
/// swift-asn1 `decode(encode(128)) == -128` class) `defaultFails` with the first
/// counterexample.
///
/// **The coder is JSON** — the round-trip holds under `JSONEncoder` /
/// `JSONDecoder`, the concrete coder named in the template's caveat. `T` must be
/// `Codable & Equatable` (to compare) and constructible from the generated
/// primitives supplied in `valueExpression`.
///
/// **Scope (this slice).** The carrier is constructed by an expression the caller
/// supplies (`valueExpression`) over the in-scope `rng`, so the corpus keeps the
/// verifier dependency-free (no strategist link). A production
/// `verify --all-from-index` over arbitrary Codable types would delegate value
/// generation to `DerivationStrategist` (PRD §11); the explicit construction
/// expression keeps this slice self-contained, exactly as
/// `ReorderPartitionStubEmitter`'s `[Int]` carrier does.
public enum CodableRoundTripStubEmitter {

    public struct Inputs: Equatable, Sendable {
        /// The `Codable & Equatable` carrier type `T`.
        public let carrierType: String
        /// A Swift expression producing a fresh `T` using the in-scope `rng`
        /// (a `StubXoshiro`), e.g. `Ratio(value: Double(rng.next() % 100))`.
        public let valueExpression: String
        /// Trials per run (deterministic under the fixed seed).
        public let trials: Int
        /// Modules to import beyond `Foundation` — e.g. the path-dependency
        /// package the carrier lives in.
        public let extraImports: [String]

        public init(
            carrierType: String,
            valueExpression: String,
            trials: Int = 1_000,
            extraImports: [String] = []
        ) {
            self.carrierType = carrierType
            self.valueExpression = valueExpression
            self.trials = trials
            self.extraImports = extraImports
        }
    }

    public static func emit(_ inputs: Inputs) -> String {
        let imports = (["Foundation"] + inputs.extraImports)
            .map { "import \($0)" }
            .joined(separator: "\n")
        return """
        // Auto-generated codable-round-trip verifier.
        // Carrier: \(inputs.carrierType) — decode(encode(x)) == x via JSON.
        \(imports)

        \(rngDefinition)

        func runCodableRoundTripCheck() -> (pass: Bool, detail: String) {
            var rng = StubXoshiro(seed: 0xC0DA_B1E5_C0DA_B1E5)
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            for _ in 0..<\(inputs.trials) {
                let value: \(inputs.carrierType) = \(inputs.valueExpression)
                do {
                    let data = try encoder.encode(value)
                    let back = try decoder.decode(\(inputs.carrierType).self, from: data)
                    if back != value {
                        return (false, "round-trip mismatch: encoded \\(value) -> decoded \\(back)")
                    }
                } catch {
                    return (false, "codec threw for \\(value): \\(error)")
                }
            }
            return (true, "")
        }

        let outcome = runCodableRoundTripCheck()
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

    /// A splitmix-seeded xoshiro256** — deterministic so a run is byte-
    /// reproducible (the measured path's determinism guarantee, cycle 118).
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
