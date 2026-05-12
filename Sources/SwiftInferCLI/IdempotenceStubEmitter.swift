import Foundation

/// V1.44.A — synthesizes the standalone Swift source for an
/// idempotence verify subprocess (`f(f(x)) ≈ f(x)` on a single function
/// `f: T -> T`).
///
/// **Shape parity with `RoundTripStubEmitter`.** Idempotence is
/// structurally identical to round-trip's single-function side — same
/// subprocess shape, same Xoshiro seeded RNG, same two-pass design
/// (default finite-domain + edge-case-biased), same `VERIFY_DEFAULT_*`
/// / `VERIFY_EDGE_*` stdout-marker contract. The V1.43.C parser
/// (`VerifyResultParser`) consumes the markers without modification.
///
/// **Marker field semantics differ from round-trip.** The parser fills
/// `forwardResult` ← `VERIFY_*_FORWARD` and `inverseResult` ← `VERIFY_*_INVERSE`
/// regardless of template; for idempotence these map to `f(x)`
/// (`onceResult`) and `f(f(x))` (`twiceResult`) respectively. The
/// renderer (V1.43.D extended at V1.44.D) interprets these fields per
/// template name so the user-facing output reads naturally.
///
/// **Carrier scope (V1.44.A).** `Complex<Double>` only — the kit's
/// `PropertyLawComplex` generator gates the carrier set the same way
/// V1.42 did for round-trip. V1.44.C extends to `Double` + `Int`.
public enum IdempotenceStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter` — identical
    /// shape, no point duplicating the nominal type.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter` — same N=100 /
    /// N=1000 semantics.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter. Mirrors `RoundTripStubEmitter.Inputs` but
    /// carries a single `functionCall` (no forward/inverse pair).
    public struct Inputs: Equatable, Sendable {
        /// The function under test, written as a call expression
        /// (e.g. `"Complex.exp"` or `"{ (z: Complex<Double>) in z }"`).
        /// The emitter appends `(value)` and `(onceResult)`; the
        /// resulting stub asserts `f(f(value)) ≈ f(value)`.
        public let functionCall: String

        /// User modules to import beyond the mandatory set. Empty
        /// entries and duplicates are filtered.
        public let extraImports: [String]

        /// Carrier type as carried on the `SemanticIndexEntry`. Must
        /// be in `supportedCarriers`; other values raise
        /// `VerifyError.unsupportedCarrier`.
        public let carrierType: String

        public let seedHex: SeedHex

        public let trialBudget: TrialBudget

        public init(
            functionCall: String,
            extraImports: [String],
            carrierType: String,
            seedHex: SeedHex,
            trialBudget: TrialBudget
        ) {
            self.functionCall = functionCall
            self.extraImports = extraImports
            self.carrierType = carrierType
            self.seedHex = seedHex
            self.trialBudget = trialBudget
        }
    }

    /// V1.44.A's supported carrier set. Single-element list; V1.44.C
    /// extends to `["Complex<Double>", "Double", "Int"]`.
    public static let supportedCarriers: [String] = ["Complex<Double>"]

    /// Emit an idempotence verify stub. Validates the carrier, then
    /// composes the source.
    public static func emit(_ inputs: Inputs) throws -> String {
        guard supportedCarriers.contains(inputs.carrierType) else {
            throw VerifyError.unsupportedCarrier(
                carrier: inputs.carrierType,
                expected: supportedCarriers
            )
        }
        return composeSource(inputs)
    }

    // MARK: - Composition

    private static func composeSource(_ inputs: Inputs) -> String {
        let importsBlock = importsSection(inputs.extraImports)
        let trials = inputs.trialBudget.count
        let header = headerSection(inputs: inputs)
        let setup = setupSection(importsBlock: importsBlock, seed: inputs.seedHex, trials: trials)
        let defaultPass = defaultPassSection(functionCall: inputs.functionCall)
        let edgePass = edgePassSection(functionCall: inputs.functionCall)
        return [header, setup, defaultPass, edgePass].joined(separator: "\n\n")
    }

    private static func headerSection(inputs: Inputs) -> String {
        """
        // V1.44.A — auto-generated two-pass idempotence verify stub.
        // Carrier: \(inputs.carrierType)
        // Function: \(inputs.functionCall) — asserts f(f(x)) ≈ f(x).
        // Pass 1 (default): inline finite-domain (Double.random in ±1e6).
        // Pass 2 (edge):    Gen<Complex<Double>>.edgeCaseBiased() from
        //                   PropertyLawComplex v2.1.0+. Skipped on default fail.
        """
    }

    private static func setupSection(importsBlock: String, seed: SeedHex, trials: Int) -> String {
        """
        \(importsBlock)

        var rng: any SeededRandomNumberGenerator = Xoshiro(seed: (
            0x\(hex(seed.stateA)),
            0x\(hex(seed.stateB)),
            0x\(hex(seed.stateC)),
            0x\(hex(seed.stateD))
        ))

        let trials = \(trials)
        """
    }

    private static func defaultPassSection(functionCall: String) -> String {
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

    /// Pass 2 stub source. Same `.rawStorage`-based edge-case matching
    /// as `RoundTripStubEmitter`'s edge pass (V1.43.E.3.b fix) so the
    /// 8 distinct non-finite curated entries resolve to their own index.
    private static func edgePassSection(functionCall: String) -> String {
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

    /// Mandatory imports for the emitted stub. Identical to the round-
    /// trip emitter's base set: `Complex<Double>` carrier + the seeded
    /// `Gen` machinery + `PropertyLawComplex`'s `edgeCaseBiased()`.
    private static func importsSection(_ extra: [String]) -> String {
        let base = ["ComplexModule", "Foundation", "PropertyBased", "PropertyLawComplex", "RealModule"]
        let extraTrimmed = extra
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let combined = Set(base + extraTrimmed).sorted()
        return combined.map { "import \($0)" }.joined(separator: "\n")
    }

    private static func hex(_ word: UInt64) -> String {
        String(word, radix: 16, uppercase: true)
    }
}
