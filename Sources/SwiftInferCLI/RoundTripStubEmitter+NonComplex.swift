import Foundation

// V1.44.B carrier — Double two-pass emission. The edge generator
// inlines the kit's `Gen<Double>.doubleWithNaN()` definition (NaN at
// ~5% per trial; the kit gates ship with a tighter coupling to
// FloatingPoint laws than the verifier needs).
extension RoundTripStubEmitter {

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
        let defaultPass = doubleDefaultPass(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
        let edgePass = doubleEdgePass(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
        return [header, setup, defaultPass, edgePass].joined(separator: "\n\n")
    }

    private static let doubleHeaderBlurb =
        "Pass 1 (default): inline finite-domain (Double.random in ±1e6).\n"
        + "// Pass 2 (edge):    inlined doubleWithNaN — NaN at ~5%, rest finite-domain."

    private static func importsForDouble(_ extra: [String]) -> String {
        let base = ["Foundation", "PropertyBased", "RealModule"]
        return mergedImports(base: base, extra: extra)
    }

    private static func doubleDefaultPass(forwardCall: String, inverseCall: String) -> String {
        """
        // --- Pass 1: default (inline finite-domain) ---

        let defaultGenerator: Generator<Double, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Double.random(in: -1_000_000.0 ... 1_000_000.0)
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

                // --- shrink phase (v1.141): minimize the failing input ---
                func roundTripFails(_ candidate: Double) -> Bool {
                    !\(inverseCall)(\(forwardCall)(candidate)).isApproximatelyEqual(to: candidate)
                }
                var shrunk = value
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for candidate in shrunk.shrink(towards: 0) where roundTripFails(candidate) {
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

    /// Double edge match: the only curated edge case is `Double.nan`,
    /// at index 0. Non-NaN failures from the 95% finite-path slice
    /// resolve to `-1`.
    private static func doubleEdgePass(forwardCall: String, inverseCall: String) -> String {
        """
        // --- Pass 2: edge-case-biased (inlined doubleWithNaN) ---

        func matchEdgeCaseIndex(_ value: Double) -> Int {
            return value.isNaN ? 0 : -1
        }

        let edgeGenerator: Generator<Double, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 20).map { tag -> Double in
                if tag == 0 { return Double.nan }
                return Double.random(in: -1_000_000.0 ... 1_000_000.0)
            }

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

// V1.44.B carrier — Int single-pass emission. No edge pass; integer
// arithmetic has no NaN/Inf semantic. The stub emits a zero-edge
// sentinel block so VerifyResultParser still produces `.bothPass`
// (with `edgeTrials: 0, edgeSampled: 0`), and the V1.44.D renderer
// detects the sentinel and shows "(integer carrier — edge pass not
// applicable)" in lieu of the curated-cases-sampled line.
extension RoundTripStubEmitter {

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
        let defaultPass = intDefaultPass(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
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

    private static func intDefaultPass(forwardCall: String, inverseCall: String) -> String {
        """
        // --- Pass 1: default (bounded-magnitude integer) ---

        let intBound = Int(1) << (Int.bitWidth / 4)
        let defaultGenerator: Generator<Int, some SendableSequenceType> =
            Gen<Int>.int(in: -intBound ... intBound)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let forwardResult = \(forwardCall)(value)
            let inverseResult = \(inverseCall)(forwardResult)
            if inverseResult != value {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(forwardResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(inverseResult)")

                // --- shrink phase (v1.141): minimize the failing input ---
                func roundTripFails(_ candidate: Int) -> Bool {
                    \(inverseCall)(\(forwardCall)(candidate)) != candidate
                }
                var shrunk = value
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for candidate in shrunk.shrink(towards: 0) where roundTripFails(candidate) {
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
