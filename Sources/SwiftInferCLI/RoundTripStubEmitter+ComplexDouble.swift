// V1.43.B carrier — Complex<Double> two-pass emission. Behavior
// bit-for-bit unchanged from v1.43.B; carved into its own extension
// so the body-length cap stays satisfied across the three carriers.
extension RoundTripStubEmitter {

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
        let defaultPass = complexDoubleDefaultPass(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
        let edgePass = complexDoubleEdgePass(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
        return [header, setup, defaultPass, edgePass].joined(separator: "\n\n")
    }

    private static let complexDoubleHeaderBlurb =
        "Pass 1 (default): inline finite-domain (Double.random in ±1e6).\n"
        + "// Pass 2 (edge):    Gen<Complex<Double>>.edgeCaseBiased() from\n"
        + "//                   PropertyLawComplex v2.1.0+. Skipped on default fail."

    /// V1.55.A — narrow per-function default-pass domain for the
    /// round-trip Complex generator. Returns a `(reMin, reMax, imMin, imMax)`
    /// quadruple as Double literals to interpolate into the stub.
    ///
    /// **Why per-function**. Cycle-51 measurement (`docs/calibration-
    /// cycle-51-findings.md`) showed the ±1e6 default range broke 8
    /// round-trip Complex EF picks because it exceeded the functions'
    /// stable domains. Cycle-52 with a uniform ±1.5 range fixed 6 of
    /// the 8 (`exp/log`, `sin/asin`, `tan/atan`, `sinh/asinh`,
    /// `tanh/atanh`) but `cos/acos` and `cosh/acosh` still failed —
    /// their principal-branch inverses return values with `Re ≥ 0`,
    /// so the round-trip only holds when `Re(input) ≥ 0`.
    ///
    /// **Cycle-52 scope**: 2 distinct domains. The lookup table can
    /// grow per function as future cycles surface other domain
    /// boundaries (e.g., `exp`'s `Im ∈ (-π, π]` principal branch when
    /// the round-trip pair includes log's branch cut).
    /// Real/imaginary range bounds (as Double literals) for the
    /// inline finite-domain default pass of a Complex round-trip.
    private struct ComplexPassDomain {
        let reMin: String
        let reMax: String
        let imMin: String
        let imMax: String
    }

    private static func complexDefaultPassDomain(forwardCall: String) -> ComplexPassDomain {
        let bareName = forwardCall.split(separator: ".").last.map(String.init) ?? forwardCall
        switch bareName {
        case "cos", "acos", "cosh", "acosh":
            // `acos`/`acosh` principal branch returns `Re ≥ 0`, so the
            // round-trip `acos(cos(z)) == z` only holds for the right
            // half-plane.
            return ComplexPassDomain(reMin: "0.0", reMax: "1.5", imMin: "-1.5", imMax: "1.5")

        default:
            // exp/log + sin/asin + tan/atan + sinh/asinh + tanh/atanh:
            // all symmetric round-trip pairs holding on `|Re| ≤ π/2`.
            return ComplexPassDomain(reMin: "-1.5", reMax: "1.5", imMin: "-1.5", imMax: "1.5")
        }
    }

    private static func complexDoubleDefaultPass(forwardCall: String, inverseCall: String) -> String {
        let domain = complexDefaultPassDomain(forwardCall: forwardCall)
        return """
        // --- Pass 1: default (inline finite-domain) ---
        //
        // V1.55.A — per-function default-pass domain. Cycle-52 evidence
        // (`git show 31a347a:docs/calibration-cycle-52-findings.md`)
        // showed the round-trip
        // property holds only within each EF pair's principal-branch
        // domain; uniform ±1e6 (v1.42) and ±1.5 (cycle-52 first cut)
        // both miss cases. cos/cosh need `Re ≥ 0` (right half-plane);
        // all other EF surface pairs use symmetric ±1.5. The v1.43 edge
        // pass still tests boundaries via Gen<Complex<Double>>
        // .edgeCaseBiased, so `.edgeCaseAdvisory` outcomes surface
        // overflow / boundary behavior beyond the principal branch.

        let defaultGenerator: Generator<Complex<Double>, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Complex(
                    Double.random(in: \(domain.reMin) ... \(domain.reMax)),
                    Double.random(in: \(domain.imMin) ... \(domain.imMax))
                )
            }

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let forwardResult = \(forwardCall)(value)
            let inverseResult = \(inverseCall)(forwardResult)
            if !inverseResult.isApproximatelyEqual(to: value) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(forwardResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(inverseResult)")
        \(complexDoubleShrinkPhase(forwardCall: forwardCall, inverseCall: inverseCall))
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// v1.141 shrink phase for the `Complex<Double>` round-trip stub.
    /// Carrier-native: shrink the real then imaginary component toward 0 (one
    /// at a time), keeping the first candidate that still breaks the round-trip,
    /// to a fixpoint. The oracle is the same `isApproximatelyEqual` check, so a
    /// shrunk value survives only if it genuinely still fails.
    private static func complexDoubleShrinkPhase(forwardCall: String, inverseCall: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing input ---
                func roundTripFails(_ candidate: Complex<Double>) -> Bool {
                    !\(inverseCall)(\(forwardCall)(candidate)).isApproximatelyEqual(to: candidate)
                }
                var shrunk = value
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for realCandidate in shrunk.real.shrink(towards: 0) {
                        let candidate = Complex(realCandidate, shrunk.imaginary)
                        if roundTripFails(candidate) {
                            shrunk = candidate
                            shrinkSteps += 1
                            continue shrinkLoop
                        }
                    }
                    for imagCandidate in shrunk.imaginary.shrink(towards: 0) {
                        let candidate = Complex(shrunk.real, imagCandidate)
                        if roundTripFails(candidate) {
                            shrunk = candidate
                            shrinkSteps += 1
                            continue shrinkLoop
                        }
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: \\(shrunk)")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }

    /// `.rawStorage`-based edge match — preserves the 8 distinct
    /// non-finite curated entries the public `.real` / `.imaginary`
    /// getters would otherwise normalize to `.nan` (V1.43.E.3.b fix).
    private static func complexDoubleEdgePass(forwardCall: String, inverseCall: String) -> String {
        """
        // --- Pass 2: edge-case-biased ---

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

        var sampledEdgeIndices: Set<Int> = []

        for trial in 0 ..< trials {
            let value = edgeGenerator.run(using: &rng)
            let matchedIndex = matchEdgeCaseIndex(value)
            if matchedIndex >= 0 { sampledEdgeIndices.insert(matchedIndex) }
            let forwardResult = \(forwardCall)(value)
            let inverseResult = \(inverseCall)(forwardResult)
            if !inverseResult.isApproximatelyEqual(to: value) {
                print("VERIFY_EDGE_RESULT: FAIL")
                print("VERIFY_EDGE_TRIAL: \\(trial)")
                print("VERIFY_EDGE_INPUT: \\(value)")
                print("VERIFY_EDGE_FORWARD: \\(forwardResult)")
                print("VERIFY_EDGE_INVERSE: \\(inverseResult)")
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
