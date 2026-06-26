import Foundation

/// V1.46.A — synthesizes the standalone Swift source for an
/// associativity verify subprocess
/// (`f(f(a, b), c) ≈ f(a, f(b, c))` on a binary function
/// `f: (T, T) -> T`).
///
/// **Shape parity with the v1.45 commutativity emitter.** Same two-pass
/// design, same Xoshiro seeded RNG, same `VERIFY_DEFAULT_*` /
/// `VERIFY_EDGE_*` stdout-marker contract. `VerifyResultParser` consumes
/// associativity output unchanged.
///
/// **Marker field semantics.** `VERIFY_*_INPUT` carries the triple as a
/// single string (`"(a, b, c)"`); `VERIFY_*_FORWARD` carries the
/// left-associated result `f(f(a, b), c)` and `VERIFY_*_INVERSE`
/// carries the right-associated result `f(a, f(b, c))`. The renderer
/// reads `templateName` to phrase these correctly.
///
/// **Three-value generation.** Each trial draws three `T` values from
/// the per-carrier generator. For the Complex<Double> / Double edge
/// passes, exactly one value per trial is drawn from the edge generator
/// — **per-slot rotation**: trial `t` puts the edge value in slot
/// `t % 3` (0 = `a`, 1 = `b`, 2 = `c`) and the other two slots draw
/// from the default finite generator. Over 100 trials this gives
/// ~34 / 33 / 33 edge draws per slot, surfacing associativity breaks
/// at any of the three nesting positions. A new `VERIFY_EDGE_SLOT`
/// marker line carries the slot index of the edge value on FAIL; the
/// parser ignores unknown marker lines, so this is purely advisory.
///
/// **Carrier scope (V1.46.A).** Same set as `CommutativityStubEmitter`
/// post-V1.45.A: `Complex<Double>`, `Double`, `Int`.
public enum AssociativityStubEmitter: SeededStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter`.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter`.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter — single binary `functionCall` plus the
    /// usual surrounding metadata.
    public struct Inputs: Equatable, Sendable, CarrierStubInputs {
        /// The function under test, written as a call expression
        /// (e.g. `"Int.add"` or
        /// `"{ (a: Int, b: Int) in a + b }"`). The emitter renders
        /// `\(functionCall)(\(functionCall)(a, b), c)` and
        /// `\(functionCall)(a, \(functionCall)(b, c))`.
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

    /// V1.46.A's supported carrier set — mirrors V1.45.A.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit an associativity verify stub. Validates the carrier first,
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

// V1.46.A carrier — Complex<Double> two-pass emission.
extension AssociativityStubEmitter {

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
        "Pass 1 (default): inline finite-domain (Double.random in ±1e6) for all 3 slots.\n"
        + "// Pass 2 (edge):    per-slot rotation — trial t draws edge into slot (t % 3),\n"
        + "//                   other two slots from the finite-default generator."

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
            let valueA = defaultGenerator.run(using: &rng)
            let valueB = defaultGenerator.run(using: &rng)
            let valueC = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(\(functionCall)(valueA, valueB), valueC)
            let rhsResult = \(functionCall)(valueA, \(functionCall)(valueB, valueC))
            if !lhsResult.isApproximatelyEqual(to: rhsResult) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(valueA), \\(valueB), \\(valueC))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
        \(complexDoubleShrinkPhase(functionCall: functionCall))
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// The `associativityFails(a, b, c)` oracle for the Complex shrink phase.
    private static func complexAssociativityOracle(functionCall: String) -> String {
        """
        func associativityFails(
                    _ aVal: Complex<Double>, _ bVal: Complex<Double>, _ cVal: Complex<Double>
                ) -> Bool {
                    let lhs = \(functionCall)(\(functionCall)(aVal, bVal), cVal)
                    let rhs = \(functionCall)(aVal, \(functionCall)(bVal, cVal))
                    return !lhs.isApproximatelyEqual(to: rhs)
                }
        """
    }

    /// v1.141 shrink phase for the `Complex<Double>` associativity stub:
    /// minimize the failing `(a, b, c)` triple one component at a time (real
    /// then imaginary of each), keeping the first candidate triple that still
    /// breaks `f(f(a, b), c) ≈ f(a, f(b, c))`.
    private static func complexDoubleShrinkPhase(functionCall: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing triple ---
                \(complexAssociativityOracle(functionCall: functionCall))
                var shrunkA = valueA
                var shrunkB = valueB
                var shrunkC = valueC
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for part in shrunkA.real.shrink(towards: 0) {
                        let candidate = Complex(part, shrunkA.imaginary)
                        if associativityFails(candidate, shrunkB, shrunkC) {
                            shrunkA = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for part in shrunkA.imaginary.shrink(towards: 0) {
                        let candidate = Complex(shrunkA.real, part)
                        if associativityFails(candidate, shrunkB, shrunkC) {
                            shrunkA = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for part in shrunkB.real.shrink(towards: 0) {
                        let candidate = Complex(part, shrunkB.imaginary)
                        if associativityFails(shrunkA, candidate, shrunkC) {
                            shrunkB = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for part in shrunkB.imaginary.shrink(towards: 0) {
                        let candidate = Complex(shrunkB.real, part)
                        if associativityFails(shrunkA, candidate, shrunkC) {
                            shrunkB = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for part in shrunkC.real.shrink(towards: 0) {
                        let candidate = Complex(part, shrunkC.imaginary)
                        if associativityFails(shrunkA, shrunkB, candidate) {
                            shrunkC = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for part in shrunkC.imaginary.shrink(towards: 0) {
                        let candidate = Complex(shrunkC.real, part)
                        if associativityFails(shrunkA, shrunkB, candidate) {
                            shrunkC = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(shrunkA), \\(shrunkB), \\(shrunkC))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }

    /// Pass 2 stub for Complex<Double>. Per-slot rotation: edge value
    /// is drawn from `Gen<Complex<Double>>.edgeCaseBiased()` and placed
    /// into slot `trial % 3`; the other two slots draw from the
    /// top-level Pass 1 `defaultGenerator`. `matchEdgeCaseIndex` runs
    /// against the edge value itself (slot-independent).
    private static func complexDoubleEdgePass(functionCall: String) -> String {
        let header = complexEdgePassHeader()
        let loop = complexEdgePassLoop(functionCall: functionCall)
        return header + "\n\n" + loop
    }

    private static func complexEdgePassHeader() -> String {
        """
        // --- Pass 2: edge-case-biased (per-slot rotation) ---

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
        // Pass 2's non-edge slots draw from Pass 1's top-level
        // `defaultGenerator`. Don't re-declare or top-level `let`
        // redeclaration fails to compile.

        var sampledEdgeIndices: Set<Int> = []
        """
    }

    private static func complexEdgePassLoop(functionCall: String) -> String {
        """
        for trial in 0 ..< trials {
            let edgeSlot = trial % 3
            let edgeValue = edgeGenerator.run(using: &rng)
            let defaultLeft = defaultGenerator.run(using: &rng)
            let defaultRight = defaultGenerator.run(using: &rng)
            let valueA: Complex<Double>
            let valueB: Complex<Double>
            let valueC: Complex<Double>
            switch edgeSlot {
            case 0:
                valueA = edgeValue
                valueB = defaultLeft
                valueC = defaultRight
            case 1:
                valueA = defaultLeft
                valueB = edgeValue
                valueC = defaultRight
            default:
                valueA = defaultLeft
                valueB = defaultRight
                valueC = edgeValue
            }
            let matchedIndex = matchEdgeCaseIndex(edgeValue)
            if matchedIndex >= 0 { sampledEdgeIndices.insert(matchedIndex) }
            let lhsResult = \(functionCall)(\(functionCall)(valueA, valueB), valueC)
            let rhsResult = \(functionCall)(valueA, \(functionCall)(valueB, valueC))
            if !lhsResult.isApproximatelyEqual(to: rhsResult) {
                print("VERIFY_EDGE_RESULT: FAIL")
                print("VERIFY_EDGE_TRIAL: \\(trial)")
                print("VERIFY_EDGE_INPUT: (\\(valueA), \\(valueB), \\(valueC))")
                print("VERIFY_EDGE_FORWARD: \\(lhsResult)")
                print("VERIFY_EDGE_INVERSE: \\(rhsResult)")
                print("VERIFY_EDGE_INDEX: \\(matchedIndex)")
                print("VERIFY_EDGE_SLOT: \\(edgeSlot)")
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

// V1.46.A shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
// Mirrors `CommutativityStubEmitter` helpers verbatim; hoist to a
// shared module-internal type during the v1.47+ helper-consolidation
// pass once a fourth template instance lands.
extension AssociativityStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.46.A — auto-generated associativity verify stub.
        // Carrier: \(inputs.carrierType)
        // Function: \(inputs.functionCall) — asserts f(f(a, b), c) ≈ f(a, f(b, c)).
        // \(carrierBlurb)
        """
    }
}
