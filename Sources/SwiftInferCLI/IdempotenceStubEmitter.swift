import Foundation

/// V1.44.A / V1.44.C — synthesizes the standalone Swift source for an
/// idempotence verify subprocess (`f(f(x)) ≈ f(x)` on a single function
/// `f: T -> T`).
///
/// **Shape parity with `RoundTripStubEmitter`.** Same two-pass design,
/// same Xoshiro seeded RNG, same `VERIFY_DEFAULT_*` / `VERIFY_EDGE_*`
/// stdout-marker contract. The V1.43.C parser (`VerifyResultParser`)
/// consumes the markers without modification.
///
/// **Marker field semantics differ from round-trip.** The parser fills
/// `forwardResult` ← `VERIFY_*_FORWARD` and `inverseResult` ← `VERIFY_*_INVERSE`
/// regardless of template; for idempotence these map to `f(x)`
/// (`onceResult`) and `f(f(x))` (`twiceResult`) respectively. The
/// V1.44.D renderer interprets the marker fields per template name.
///
/// **Carrier scope (V1.44.C).** Three carriers — same set as
/// `RoundTripStubEmitter` post-V1.44.B:
///
///   - `Complex<Double>`: two-pass (default finite + `Gen<Complex<Double>>.edgeCaseBiased()`).
///   - `Double`: two-pass with inlined `doubleWithNaN` equivalent.
///   - `Int`: single-pass with inlined `boundedForArithmetic` equivalent
///     + zero-edge sentinel so `VerifyResultParser` still produces `.bothPass`.
public enum IdempotenceStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter`.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter`.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter. Mirrors `RoundTripStubEmitter.Inputs` but
    /// carries a single `functionCall` (idempotence is single-function).
    public struct Inputs: Equatable, Sendable {
        public let functionCall: String
        public let extraImports: [String]
        public let carrierType: String
        public let seedHex: SeedHex
        public let trialBudget: TrialBudget
        /// V1.49.A — verbatim Swift source rendered between the
        /// imports + the `var rng = ...` line. See `RoundTripStubEmitter.Inputs.preamble`
        /// for the load-bearing docstring.
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

    /// V1.44.C's supported carrier set — mirrors `RoundTripStubEmitter`.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit an idempotence verify stub. Validates the carrier first,
    /// then dispatches to the per-carrier composer.
    public static func emit(_ inputs: Inputs) throws -> String {
        guard let carrier = CarrierKind.from(typeName: inputs.carrierType) else {
            throw VerifyError.unsupportedCarrier(
                carrier: inputs.carrierType,
                expected: supportedCarriers
            )
        }
        switch carrier {
        case .complexDouble: return composeComplexDoubleSource(inputs)
        case .double: return composeDoubleSource(inputs)
        case .int: return composeIntSource(inputs)
        }
    }

    // MARK: - Carrier dispatch

    /// Internal carrier discriminator — mirrors
    /// `RoundTripStubEmitter.CarrierKind` (intentionally duplicated to
    /// keep the two emitters' implementation details independent;
    /// promote to a shared module-internal type when a third template
    /// reuses it).
    private enum CarrierKind {
        case complexDouble
        case double
        case int

        static func from(typeName: String) -> CarrierKind? {
            switch typeName {
            case "Complex<Double>": return .complexDouble
            case "Double": return .double
            case "Int": return .int
            default: return nil
            }
        }
    }
}

// V1.44.A carrier — Complex<Double> two-pass emission. Behavior
// bit-for-bit unchanged from V1.44.A.
extension IdempotenceStubEmitter {

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
        + "// Pass 2 (edge):    Gen<Complex<Double>>.edgeCaseBiased() from\n"
        + "//                   PropertyLawComplex v2.1.0+. Skipped on default fail."

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
            let value = defaultGenerator.run(using: &rng)
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if !twiceResult.isApproximatelyEqual(to: onceResult) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// `.rawStorage`-based edge match — same V1.43.E.3.b fix as
    /// `RoundTripStubEmitter`.
    private static func complexDoubleEdgePass(functionCall: String) -> String {
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
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if !twiceResult.isApproximatelyEqual(to: onceResult) {
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

// V1.44.C shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
extension IdempotenceStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.44.C — auto-generated idempotence verify stub.
        // Carrier: \(inputs.carrierType)
        // Function: \(inputs.functionCall) — asserts f(f(x)) ≈ f(x).
        // \(carrierBlurb)
        """
    }

    static func setupSection(
        importsBlock: String,
        seed: SeedHex,
        trials: Int,
        preamble: String = ""
    ) -> String {
        let preambleBlock = preamble.isEmpty ? "" : "\n\(preamble)\n"
        return """
        \(importsBlock)
        \(preambleBlock)
        var rng: any SeededRandomNumberGenerator = Xoshiro(seed: (
            0x\(hex(seed.stateA)),
            0x\(hex(seed.stateB)),
            0x\(hex(seed.stateC)),
            0x\(hex(seed.stateD))
        ))

        let trials = \(trials)
        """
    }

    static func mergedImports(base: [String], extra: [String]) -> String {
        let extraTrimmed = extra
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let combined = Set(base + extraTrimmed).sorted()
        return combined.map { "import \($0)" }.joined(separator: "\n")
    }

    static func hex(_ word: UInt64) -> String {
        String(word, radix: 16, uppercase: true)
    }
}
