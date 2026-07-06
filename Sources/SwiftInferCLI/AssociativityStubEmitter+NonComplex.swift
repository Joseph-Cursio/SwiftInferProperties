import Foundation

// V1.46.A carrier — Double two-pass associativity emission. Mirrors
// `CommutativityStubEmitter+NonComplex.swift`'s `composeDoubleSource`
// but for the `f(f(a, b), c) ≈ f(a, f(b, c))` shape: each trial draws
// three values; the edge pass per-slot-rotates the curated real-axis
// edge generator (`DoubleEdgeCaseStub`, ~10%) across slots a/b/c.
extension AssociativityStubEmitter {

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
        "Pass 1 (default): inline finite-domain (Double.random in ±1e6) for all 3 slots.\n"
        + "// Pass 2 (edge):    per-slot rotation — trial t draws the real-axis edge set\n"
        + "//                   into slot (t % 3), other two slots from the finite-default generator."

    private static func importsForDouble(_ extra: [String]) -> String {
        let base = ["Foundation", "PropertyBased", "RealModule"]
        return mergedImports(base: base, extra: extra)
    }

    private static func doubleDefaultPass(functionCall: String) -> String {
        let oracle = "!sameResult(\(functionCall)(\(functionCall)(aValue, bValue), cValue), "
            + "\(functionCall)(aValue, \(functionCall)(bValue, cValue)))"
        let shrink = scalarShrinkPhase(carrier: "Double", oracle: oracle)
        return """
        // --- Pass 1: default (inline finite-domain) ---

        let defaultGenerator: Generator<Double, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Double.random(in: -1_000_000.0 ... 1_000_000.0)
            }

        for trial in 0 ..< trials {
            let valueA = defaultGenerator.run(using: &rng)
            let valueB = defaultGenerator.run(using: &rng)
            let valueC = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(\(functionCall)(valueA, valueB), valueC)
            let rhsResult = \(functionCall)(valueA, \(functionCall)(valueB, valueC))
            if !sameResult(lhsResult, rhsResult) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(valueA), \\(valueB), \\(valueC))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// v1.141 shrink phase for a scalar (`Int` / `Double`) associativity
    /// triple: shrink `valueA`, `valueB`, then `valueC` toward 0, keeping the
    /// first candidate triple that still satisfies `oracle` (a Bool expression
    /// over `aValue` / `bValue` / `cValue`).
    private static func scalarShrinkPhase(carrier: String, oracle: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing triple ---
                func associativityFails(_ aValue: \(carrier), _ bValue: \(carrier), _ cValue: \(carrier)) -> Bool {
                    \(oracle)
                }
                var shrunkA = valueA
                var shrunkB = valueB
                var shrunkC = valueC
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for part in shrunkA.shrink(towards: 0) where associativityFails(part, shrunkB, shrunkC) {
                        shrunkA = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    for part in shrunkB.shrink(towards: 0) where associativityFails(shrunkA, part, shrunkC) {
                        shrunkB = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    for part in shrunkC.shrink(towards: 0) where associativityFails(shrunkA, shrunkB, part) {
                        shrunkC = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(shrunkA), \\(shrunkB), \\(shrunkC))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }

    /// Double edge match: the curated real-axis set (`DoubleEdgeCaseStub`);
    /// NaN/±Inf/±0/overflow/subnormal → their index, finite-slice → -1.
    /// Applied to the edge value itself (the one drawn from the real-axis
    /// edge generator), regardless of which slot it lands in.
    private static func doubleEdgePass(functionCall: String) -> String {
        let trialLoop = doubleEdgePassTrialLoop(functionCall: functionCall)
        return """
        // --- Pass 2: edge-case-biased (real-axis edge set; per-slot rotation) ---

        \(DoubleEdgeCaseStub.matchFunctionSource)

        \(DoubleEdgeCaseStub.generatorSource)
        // Pass 2's non-edge slots reuse Pass 1's top-level `defaultGenerator`.

        var sampledEdgeIndices: Set<Int> = []

        \(trialLoop)

        print("VERIFY_EDGE_RESULT: PASS")
        print("VERIFY_EDGE_TRIALS: \\(trials)")
        print("VERIFY_EDGE_SAMPLED: \\(sampledEdgeIndices.count)")
        exit(0)
        """
    }

    /// V1.89 lint pass — extracted from `doubleEdgePass` so the
    /// emitted-source builder stays under SwiftLint's 50-line cap.
    /// Per-trial loop body: per-slot rotation of the edge value across
    /// the three associativity slots (A/B/C), associativity check,
    /// FAIL print + trap on mismatch.
    private static func doubleEdgePassTrialLoop(functionCall: String) -> String {
        """
        for trial in 0 ..< trials {
            let edgeSlot = trial % 3
            let edgeValue = edgeGenerator.run(using: &rng)
            let defaultLeft = defaultGenerator.run(using: &rng)
            let defaultRight = defaultGenerator.run(using: &rng)
            let valueA: Double
            let valueB: Double
            let valueC: Double
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
            if !sameResult(lhsResult, rhsResult) {
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
        """
    }
}

// V1.46.A carrier — Int single-pass associativity emission. Same
// zero-edge-sentinel pattern as the v1.44 / v1.45 emitters' Int path:
// integer arithmetic has no NaN/Inf semantic, so no edge pass.
extension AssociativityStubEmitter {

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
        let oracle = "\(functionCall)(\(functionCall)(aValue, bValue), cValue)"
            + " != \(functionCall)(aValue, \(functionCall)(bValue, cValue))"
        let shrink = scalarShrinkPhase(carrier: "Int", oracle: oracle)
        return """
        // --- Pass 1: default (bounded-magnitude integer) ---

        let intBound = Int(1) << (Int.bitWidth / 4)
        let defaultGenerator: Generator<Int, some SendableSequenceType> =
            Gen<Int>.int(in: -intBound ... intBound)

        for trial in 0 ..< trials {
            let valueA = defaultGenerator.run(using: &rng)
            let valueB = defaultGenerator.run(using: &rng)
            let valueC = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(\(functionCall)(valueA, valueB), valueC)
            let rhsResult = \(functionCall)(valueA, \(functionCall)(valueB, valueC))
            if lhsResult != rhsResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(valueA), \\(valueB), \\(valueC))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
        \(shrink)
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
