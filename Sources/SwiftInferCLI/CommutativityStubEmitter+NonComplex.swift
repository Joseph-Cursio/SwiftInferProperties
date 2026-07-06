import Foundation

// V1.45.A carrier — Double two-pass commutativity emission. Mirrors
// `IdempotenceStubEmitter+NonComplex.swift`'s `composeDoubleSource`
// but for the `f(a, b) ≈ f(b, a)` shape: each trial draws two values;
// the edge pass biases the first to the curated real-axis edge set
// (`DoubleEdgeCaseStub`, ~10%) and draws the second from the default
// finite generator.
extension CommutativityStubEmitter {

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
        + "// Pass 2 (edge):    first value biased to the real-axis edge set,\n"
        + "//                   second value drawn from the finite-default generator."

    private static func importsForDouble(_ extra: [String]) -> String {
        let base = ["Foundation", "PropertyBased", "RealModule"]
        return mergedImports(base: base, extra: extra)
    }

    private static func doubleDefaultPass(functionCall: String) -> String {
        let oracle = "!sameResult(\(functionCall)(aValue, bValue), \(functionCall)(bValue, aValue))"
        let shrink = scalarShrinkPhase(carrier: "Double", oracle: oracle)
        return """
        // --- Pass 1: default (inline finite-domain) ---

        let defaultGenerator: Generator<Double, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Double.random(in: -1_000_000.0 ... 1_000_000.0)
            }

        for trial in 0 ..< trials {
            let lhs = defaultGenerator.run(using: &rng)
            let rhs = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if !sameResult(lhsResult, rhsResult) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(lhs), \\(rhs))")
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

    /// Double edge match: the curated real-axis set (`DoubleEdgeCaseStub`);
    /// NaN/±Inf/±0/overflow/subnormal → their index, finite-slice → -1.
    /// Applied to `lhs` only (the edge-biased value).
    private static func doubleEdgePass(functionCall: String) -> String {
        """
        // --- Pass 2: edge-case-biased (real-axis edge set; lhs only) ---

        \(DoubleEdgeCaseStub.matchFunctionSource)

        \(DoubleEdgeCaseStub.generatorSource)
        // Pass 2's rhs reuses Pass 1's top-level `defaultGenerator`.

        var sampledEdgeIndices: Set<Int> = []

        for trial in 0 ..< trials {
            let lhs = edgeGenerator.run(using: &rng)
            let rhs = defaultGenerator.run(using: &rng)
            let matchedIndex = matchEdgeCaseIndex(lhs)
            if matchedIndex >= 0 { sampledEdgeIndices.insert(matchedIndex) }
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if !sameResult(lhsResult, rhsResult) {
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

// V1.45.A carrier — Int single-pass commutativity emission. Same
// zero-edge-sentinel pattern as the v1.44 emitters' Int path: integer
// arithmetic has no NaN/Inf semantic, so no edge pass.
extension CommutativityStubEmitter {

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
        let oracle = "\(functionCall)(aValue, bValue) != \(functionCall)(bValue, aValue)"
        let shrink = scalarShrinkPhase(carrier: "Int", oracle: oracle)
        return """
        // --- Pass 1: default (bounded-magnitude integer) ---

        let intBound = Int(1) << (Int.bitWidth / 4)
        let defaultGenerator: Generator<Int, some SendableSequenceType> =
            Gen<Int>.int(in: -intBound ... intBound)

        for trial in 0 ..< trials {
            let lhs = defaultGenerator.run(using: &rng)
            let rhs = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if lhsResult != rhsResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(lhs), \\(rhs))")
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

    /// v1.141 shrink phase for a scalar (`Int` / `Double`) commutativity pair:
    /// shrink `lhs` then `rhs` toward 0, keeping the first candidate pair that
    /// still satisfies `oracle` (a Bool expression over `aValue` / `bValue`).
    private static func scalarShrinkPhase(carrier: String, oracle: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing pair ---
                func commutativityFails(_ aValue: \(carrier), _ bValue: \(carrier)) -> Bool {
                    \(oracle)
                }
                var shrunkLhs = lhs
                var shrunkRhs = rhs
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for candidate in shrunkLhs.shrink(towards: 0) where commutativityFails(candidate, shrunkRhs) {
                        shrunkLhs = candidate; shrinkSteps += 1; continue shrinkLoop
                    }
                    for candidate in shrunkRhs.shrink(towards: 0) where commutativityFails(shrunkLhs, candidate) {
                        shrunkRhs = candidate; shrinkSteps += 1; continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(shrunkLhs), \\(shrunkRhs))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
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
