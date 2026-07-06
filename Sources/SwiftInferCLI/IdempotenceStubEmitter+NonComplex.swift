import Foundation

// V1.44.C carrier — Double two-pass idempotence emission. Mirrors
// `RoundTripStubEmitter+NonComplex.swift`'s `composeDoubleSource` but
// for the `f(f(x)) ≈ f(x)` shape: emits `onceResult = f(value)` +
// `twiceResult = f(onceResult)` per trial; equality check is
// `sameResult(twiceResult, onceResult)` (NaN-reflexive — see
// `SeededStubEmitter.nanReflexiveDoubleEquality`).
extension IdempotenceStubEmitter {

    static func composeDoubleSource(_ inputs: Inputs) -> String {
        let importsBlock = importsForDouble(inputs.extraImports)
        let trials = inputs.trialBudget.count
        let header = headerSection(inputs: inputs, carrierBlurb: doubleHeaderBlurb)
        let setup = setupSection(
            importsBlock: importsBlock,
            seed: inputs.seedHex,
            trials: trials,
            preamble: inputs.preamble
        )
        let defaultPass = doubleDefaultPass(functionCall: inputs.functionCall)
        let edgePass = doubleEdgePass(functionCall: inputs.functionCall)
        return [header, setup, nanReflexiveDoubleEquality, defaultPass, edgePass]
            .joined(separator: "\n\n")
    }

    private static let doubleHeaderBlurb =
        "Pass 1 (default): inline finite-domain (Double.random in ±1e6).\n"
        + "// Pass 2 (edge):    real-axis edge set (NaN/±Inf/±0/overflow/subnormal at ~10%)."

    private static func importsForDouble(_ extra: [String]) -> String {
        let base = ["Foundation", "PropertyBased", "RealModule"]
        return mergedImports(base: base, extra: extra)
    }

    private static func doubleDefaultPass(functionCall: String) -> String {
        """
        // --- Pass 1: default (inline finite-domain) ---

        let defaultGenerator: Generator<Double, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Double.random(in: -1_000_000.0 ... 1_000_000.0)
            }

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if !sameResult(twiceResult, onceResult) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")

                // --- shrink phase (v1.141): minimize the failing input ---
                func idempotenceFails(_ candidate: Double) -> Bool {
                    let onceCandidate = \(functionCall)(candidate)
                    return !sameResult(\(functionCall)(onceCandidate), onceCandidate)
                }
                var shrunk = value
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for candidate in shrunk.shrink(towards: 0) where idempotenceFails(candidate) {
                        shrunk = candidate
                        shrinkSteps += 1
                        continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: \\(shrunk)")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// Double edge match: the curated real-axis set (`DoubleEdgeCaseStub`);
    /// NaN/±Inf/±0/overflow/subnormal → their index, finite-slice → -1.
    private static func doubleEdgePass(functionCall: String) -> String {
        """
        // --- Pass 2: edge-case-biased (real-axis edge set) ---

        \(DoubleEdgeCaseStub.matchFunctionSource)

        \(DoubleEdgeCaseStub.generatorSource)

        var sampledEdgeIndices: Set<Int> = []

        for trial in 0 ..< trials {
            let value = edgeGenerator.run(using: &rng)
            let matchedIndex = matchEdgeCaseIndex(value)
            if matchedIndex >= 0 { sampledEdgeIndices.insert(matchedIndex) }
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if !sameResult(twiceResult, onceResult) {
                print("VERIFY_EDGE_RESULT: FAIL")
                print("VERIFY_EDGE_TRIAL: \\(trial)")
                print("VERIFY_EDGE_INPUT: \\(value)")
                print("VERIFY_EDGE_FORWARD: \\(onceResult)")
                print("VERIFY_EDGE_INVERSE: \\(twiceResult)")
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

// V1.44.C carrier — Int single-pass idempotence emission. Same
// zero-edge-sentinel pattern as `RoundTripStubEmitter+NonComplex.swift`'s
// `composeIntSource` so VerifyResultParser produces `.bothPass` with
// `edgeTrials: 0, edgeSampled: 0`; the V1.44.D renderer surfaces
// "(integer carrier — edge pass not applicable)".
extension IdempotenceStubEmitter {

    static func composeIntSource(_ inputs: Inputs) -> String {
        let importsBlock = importsForInt(inputs.extraImports)
        let trials = inputs.trialBudget.count
        let header = headerSection(inputs: inputs, carrierBlurb: intHeaderBlurb)
        let setup = setupSection(
            importsBlock: importsBlock,
            seed: inputs.seedHex,
            trials: trials,
            preamble: inputs.preamble
        )
        let defaultPass = intDefaultPass(functionCall: inputs.functionCall)
        let edgeSentinel = intEdgeSentinel()
        return [header, setup, defaultPass, edgeSentinel].joined(separator: "\n\n")
    }

    private static let intHeaderBlurb =
        "Single-pass: inlined boundedForArithmetic — sampled in ±(1 << (Int.bitWidth/4)).\n"
        + "// No edge pass; integer arithmetic has no NaN/Inf semantic."

    private static func importsForInt(_ extra: [String]) -> String {
        let base = ["Foundation", "PropertyBased"]
        return mergedImports(base: base, extra: extra)
    }

    private static func intDefaultPass(functionCall: String) -> String {
        """
        // --- Pass 1: default (bounded-magnitude integer) ---

        let intBound = Int(1) << (Int.bitWidth / 4)
        let defaultGenerator: Generator<Int, some SendableSequenceType> =
            Gen<Int>.int(in: -intBound ... intBound)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if twiceResult != onceResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")

                // --- shrink phase (v1.141): minimize the failing input ---
                func idempotenceFails(_ candidate: Int) -> Bool {
                    let onceCandidate = \(functionCall)(candidate)
                    return \(functionCall)(onceCandidate) != onceCandidate
                }
                var shrunk = value
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for candidate in shrunk.shrink(towards: 0) where idempotenceFails(candidate) {
                        shrunk = candidate
                        shrinkSteps += 1
                        continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: \\(shrunk)")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    private static func intEdgeSentinel() -> String {
        """
        // --- Pass 2: edge-case-biased — n/a for integer carrier ---
        print("VERIFY_EDGE_RESULT: PASS")
        print("VERIFY_EDGE_TRIALS: 0")
        print("VERIFY_EDGE_SAMPLED: 0")
        exit(0)
        """
    }
}
