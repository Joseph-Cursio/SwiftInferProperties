import Foundation

/// V1.45.A — synthesizes the standalone Swift source for a
/// commutativity verify subprocess (`f(a, b) ≈ f(b, a)` on a binary
/// function `f: (T, T) -> T`).
///
/// **Shape parity with the v1.44 emitters.** Same two-pass design,
/// same Xoshiro seeded RNG, same `VERIFY_DEFAULT_*` / `VERIFY_EDGE_*`
/// stdout-marker contract. `VerifyResultParser` consumes commutativity
/// output unchanged.
///
/// **Marker field semantics.** `VERIFY_*_INPUT` carries the pair as a
/// single string (`"(lhs, rhs)"`); `VERIFY_*_FORWARD` carries
/// `f(lhs, rhs)` (the original-order result) and `VERIFY_*_INVERSE`
/// carries `f(rhs, lhs)` (the swapped-order result). The V1.44.D
/// renderer reads `templateName` to phrase these correctly.
///
/// **Two-value generation.** Each trial draws two `T` values from the
/// per-carrier generator. For the Complex<Double> / Double edge
/// passes, the **first** value is biased to the edge generator and
/// the **second** is drawn from the default finite generator. This
/// gives `~10 edge × finite` pairings per 100 trials (vs `~1 edge ×
/// edge` if both were biased), surfacing the advisory signal at half
/// the cost — symmetric pairing would compound the point-at-infinity
/// equality collapse on Complex.
///
/// **Carrier scope (V1.45.A).** Same set as `IdempotenceStubEmitter`
/// post-V1.44.C: `Complex<Double>`, `Double`, `Int`.
public enum CommutativityStubEmitter: SeededStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter`.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter`.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter — single binary `functionCall` plus the
    /// usual surrounding metadata.
    public struct Inputs: Equatable, Sendable, CarrierStubInputs {
        /// The function under test, written as a call expression
        /// (e.g. `"Int.binomial"` or
        /// `"{ (a: Int, b: Int) in a + b }"`). The emitter renders
        /// `\(functionCall)(lhs, rhs)` and `\(functionCall)(rhs, lhs)`.
        public let functionCall: String

        /// User modules to import beyond the carrier-specific
        /// mandatory set. Empty entries and duplicates are filtered.
        public let extraImports: [String]

        /// Carrier type. Must be in `supportedCarriers`.
        public let carrierType: String

        public let seedHex: SeedHex

        public let trialBudget: TrialBudget

        /// V1.49.A — verbatim Swift source rendered between the
        /// imports + the `var rng = ...` line. See
        /// `RoundTripStubEmitter.Inputs.preamble` for the load-bearing docstring.
        public let preamble: String

        public init(
            functionCall: String,
            extraImports: [String],
            carrierType: String,
            seedHex: SeedHex,
            trialBudget: TrialBudget,
            preamble: String = ""
        ) {
            self.functionCall = functionCall
            self.extraImports = extraImports
            self.carrierType = carrierType
            self.seedHex = seedHex
            self.trialBudget = trialBudget
            self.preamble = preamble
        }
    }

    /// V1.45.A's supported carrier set — mirrors V1.44 emitters.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit a commutativity verify stub. Validates the carrier first,
    /// then dispatches to the per-carrier composer.
    public static func emit(_ inputs: Inputs) throws -> String {
        try CarrierStubDispatch.emit(
            inputs,
            supportedCarriers: supportedCarriers,
            complexDouble: composeComplexDoubleSource,
            double: composeDoubleSource,
            int: composeIntSource
        )
    }
}

// V1.45.A carrier — Complex<Double> two-pass emission.
extension CommutativityStubEmitter {

    static func composeComplexDoubleSource(_ inputs: Inputs) -> String {
        let importsBlock = importsForComplexDouble(inputs.extraImports)
        let trials = inputs.trialBudget.count
        let header = headerSection(inputs: inputs, carrierBlurb: complexDoubleHeaderBlurb)
        let setup = setupSection(
            importsBlock: importsBlock,
            seed: inputs.seedHex,
            trials: trials,
            preamble: inputs.preamble
        )
        let defaultPass = complexDoubleDefaultPass(functionCall: inputs.functionCall)
        let edgePass = complexDoubleEdgePass(functionCall: inputs.functionCall)
        return [header, setup, defaultPass, edgePass].joined(separator: "\n\n")
    }

    private static let complexDoubleHeaderBlurb =
        "Pass 1 (default): inline finite-domain (Double.random in ±1e6).\n"
        + "// Pass 2 (edge):    first value biased to Gen<Complex<Double>>.edgeCaseBiased(),\n"
        + "//                   second value drawn from the finite-default generator."

    private static func importsForComplexDouble(_ extra: [String]) -> String {
        let base = ["ComplexModule", "Foundation", "PropertyBased", "PropertyLawComplex", "RealModule"]
        return mergedImports(base: base, extra: extra)
    }

    private static func complexDoubleDefaultPass(functionCall: String) -> String {
        """
        // --- Pass 1: default (inline finite-domain) ---

        let defaultGenerator: Generator<Complex<Double>, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Complex(
                    Double.random(in: -1_000_000.0 ... 1_000_000.0),
                    Double.random(in: -1_000_000.0 ... 1_000_000.0)
                )
            }

        for trial in 0 ..< trials {
            let lhs = defaultGenerator.run(using: &rng)
            let rhs = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if !lhsResult.isApproximatelyEqual(to: rhsResult) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(lhs), \\(rhs))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// Pass 2 stub for Complex<Double>. First value biased to the
    /// kit's `edgeCaseBiased()`; second value drawn from the default
    /// finite generator. `matchEdgeCaseIndex` runs against the
    /// edge-side `lhs` only — the failing-input string still carries
    /// both values for context.
    private static func complexDoubleEdgePass(functionCall: String) -> String {
        let header = complexEdgePassHeader()
        let loop = complexEdgePassLoop(functionCall: functionCall)
        return header + "\n\n" + loop
    }

    private static func complexEdgePassHeader() -> String {
        """
        // --- Pass 2: edge-case-biased (lhs only) ---

        func matchEdgeCaseIndex(_ value: Complex<Double>) -> Int {
            let entries = Gen<Complex<Double>>.complexEdgeCases
            let valueStorage = value.rawStorage
            for index in entries.indices {
                let entryStorage = entries[index].rawStorage
                let realMatch = entryStorage.x.isNaN
                    ? valueStorage.x.isNaN
                    : entryStorage.x == valueStorage.x
                let imagMatch = entryStorage.y.isNaN
                    ? valueStorage.y.isNaN
                    : entryStorage.y == valueStorage.y
                if realMatch && imagMatch { return index }
            }
            return -1
        }

        let edgeGenerator: Generator<Complex<Double>, some SendableSequenceType> =
            Gen<Complex<Double>>.edgeCaseBiased()
        // Pass 2's rhs draws from Pass 1's `defaultGenerator` — already
        // declared at top-level scope so it's reachable here. Don't
        // re-declare or top-level `let` redeclaration fails to compile.

        var sampledEdgeIndices: Set<Int> = []
        """
    }

    private static func complexEdgePassLoop(functionCall: String) -> String {
        """
        for trial in 0 ..< trials {
            let lhs = edgeGenerator.run(using: &rng)
            let rhs = defaultGenerator.run(using: &rng)
            let matchedIndex = matchEdgeCaseIndex(lhs)
            if matchedIndex >= 0 { sampledEdgeIndices.insert(matchedIndex) }
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if !lhsResult.isApproximatelyEqual(to: rhsResult) {
                print("VERIFY_EDGE_RESULT: FAIL")
                print("VERIFY_EDGE_TRIAL: \\(trial)")
                print("VERIFY_EDGE_INPUT: (\\(lhs), \\(rhs))")
                print("VERIFY_EDGE_FORWARD: \\(lhsResult)")
                print("VERIFY_EDGE_INVERSE: \\(rhsResult)")
                print("VERIFY_EDGE_INDEX: \\(matchedIndex)")
                exit(1)
            }
        }

        print("VERIFY_EDGE_RESULT: PASS")
        print("VERIFY_EDGE_TRIALS: \\(trials)")
        print("VERIFY_EDGE_SAMPLED: \\(sampledEdgeIndices.count)")
        exit(0)
        """
    }
}

// V1.45.A shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
extension CommutativityStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.45.A — auto-generated commutativity verify stub.
        // Carrier: \(inputs.carrierType)
        // Function: \(inputs.functionCall) — asserts f(a, b) ≈ f(b, a).
        // \(carrierBlurb)
        """
    }
}
