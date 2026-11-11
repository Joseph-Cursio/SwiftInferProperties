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
        \(complexDoubleShrinkPhase(functionCall: functionCall))
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// v1.141 shrink phase for the `Complex<Double>` commutativity stub:
    /// minimize the failing `(lhs, rhs)` pair one component at a time (real
    /// then imaginary of each), keeping the first candidate pair that still
    /// breaks `f(a, b) ≈ f(b, a)`.
    private static func complexDoubleShrinkPhase(functionCall: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing pair ---
                func commutativityFails(_ aValue: Complex<Double>, _ bValue: Complex<Double>) -> Bool {
                    !\(functionCall)(aValue, bValue).isApproximatelyEqual(to: \(functionCall)(bValue, aValue))
                }
                var shrunkLhs = lhs
                var shrunkRhs = rhs
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for component in shrunkLhs.real.shrink(towards: 0) {
                        let candidate = Complex(component, shrunkLhs.imaginary)
                        if commutativityFails(candidate, shrunkRhs) {
                            shrunkLhs = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for component in shrunkLhs.imaginary.shrink(towards: 0) {
                        let candidate = Complex(shrunkLhs.real, component)
                        if commutativityFails(candidate, shrunkRhs) {
                            shrunkLhs = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for component in shrunkRhs.real.shrink(towards: 0) {
                        let candidate = Complex(component, shrunkRhs.imaginary)
                        if commutativityFails(shrunkLhs, candidate) {
                            shrunkRhs = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    for component in shrunkRhs.imaginary.shrink(towards: 0) {
                        let candidate = Complex(shrunkRhs.real, component)
                        if commutativityFails(shrunkLhs, candidate) {
                            shrunkRhs = candidate; shrinkSteps += 1; continue shrinkLoop
                        }
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(shrunkLhs), \\(shrunkRhs))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
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
