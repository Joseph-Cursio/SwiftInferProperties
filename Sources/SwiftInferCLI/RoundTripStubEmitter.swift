import Foundation

/// V1.42.C.2 — synthesizes the standalone Swift source for a round-trip
/// verify subprocess.
///
/// **Scope of V1.42.C.2.** Pure-function emission. Caller supplies
/// already-resolved `forwardName` / `inverseName` / `userModuleName` /
/// `carrierType` / `seedHex` / `trialBudget`; the emitter returns the
/// complete `main.swift`-shaped source string ready for V1.42.C.3 to
/// drop into a synthesized SwiftPM workdir.
///
/// **Carrier scope.** V1.42 supports `Complex<Double>` only. Other
/// carriers throw `.unsupportedCarrier`. The kit's
/// `PropertyLawComplex` generator (v2.1.0) is the gating constraint:
/// extending the carrier set means landing matching kit-side generators
/// first.
///
/// **Generator choice (V1.43.B).** Two consecutive passes share the
/// same `Xoshiro` RNG:
///
///   - **Default pass** — inline finite-domain generator
///     (`Double.random(in: -1e6 ... 1e6)` for each component). Behavior
///     is bit-for-bit identical to v1.42's single pass so cycle-27-era
///     expectations don't shift.
///   - **Edge-case pass** — `Gen<Complex<Double>>.edgeCaseBiased()`
///     from `PropertyLawComplex` (90/10 mix of finite-domain + curated
///     12-entry edge cases). Only runs if the default pass passed
///     (short-circuit per the proposal §2.2 row 3 — "Property is
///     wrong; skip edge pass").
///
/// **Output shape.** The stub emits per-pass `VERIFY_DEFAULT_*` and
/// `VERIFY_EDGE_*` markers:
///
///   - Default fail → exit 1 with `VERIFY_DEFAULT_RESULT: FAIL` +
///     trial / input / forward / inverse (no `VERIFY_EDGE_*` lines).
///   - Edge fail → exit 1 with `VERIFY_DEFAULT_RESULT: PASS` +
///     `VERIFY_EDGE_RESULT: FAIL` + trial / input / forward / inverse
///     / index. The index is the 0-based position into
///     `Gen<Complex<Double>>.complexEdgeCases` (NaN-aware match), or
///     `-1` if the failing value came from the 90% finite-path slice.
///   - Both pass → exit 0 with `VERIFY_DEFAULT_RESULT: PASS` +
///     `VERIFY_EDGE_RESULT: PASS` + per-pass trial counts +
///     `VERIFY_EDGE_SAMPLED: <N>` (distinct curated entries hit).
///
/// V1.43.C/D parse the `VERIFY_*` lines and render the 4-outcome table
/// (`bothPass` / `edgeCaseAdvisory` / `defaultFails` / `error`).
public enum RoundTripStubEmitter {

    /// Hex-formatted Xoshiro seed quadruple. A nominal type so callers
    /// can document their seed-derivation strategy without leaking a
    /// 4-tuple type through the API (the `large_tuple` lint rule caps
    /// at 2 members).
    public struct SeedHex: Equatable, Sendable {
        public let stateA: UInt64
        public let stateB: UInt64
        public let stateC: UInt64
        public let stateD: UInt64

        public init(stateA: UInt64, stateB: UInt64, stateC: UInt64, stateD: UInt64) {
            self.stateA = stateA
            self.stateB = stateB
            self.stateC = stateC
            self.stateD = stateD
        }
    }

    /// Trial-budget literal that lands in the emitted stub.
    public enum TrialBudget: Equatable, Sendable {
        case small   // N=100, V1.42 default
        case standard // N=1000, the v1.45+ accept-flow integration default

        public var count: Int {
            switch self {
            case .small: return 100
            case .standard: return 1000
            }
        }
    }

    /// Inputs to the emitter — collected into a struct rather than a
    /// long parameter list so the call sites stay readable and the
    /// `function_parameter_count` lint rule doesn't fire.
    public struct Inputs: Equatable, Sendable {
        /// Forward-side function call as it would appear at the call
        /// site. E.g. `"Complex.exp"` (no argument list — the emitter
        /// appends `(value)`), or `"Foo.encode"`. The emitter does not
        /// validate this is a syntactically-valid Swift expression; the
        /// `swift build` step in V1.42.C.3 surfaces typos as build
        /// errors.
        public let forwardCall: String

        /// Inverse-side function call. Same convention as
        /// `forwardCall`. The emitter renders
        /// `\(inverseCall)(\(forwardCall)(value))`.
        public let inverseCall: String

        /// User module(s) to import beyond the V1.42-mandatory
        /// `ComplexModule` / `RealModule` / `Foundation`. For
        /// verifying the kit's own `Complex.exp` / `Complex.log` this
        /// can be empty. For verifying user-defined functions over
        /// `Complex<Double>` this contains the user's target name.
        /// Empty entries and duplicates are filtered.
        public let extraImports: [String]

        /// Carrier type as carried on the SemanticIndexEntry. Must be
        /// `"Complex<Double>"` in v1.42; other carriers throw
        /// `.unsupportedCarrier`.
        public let carrierType: String

        /// Xoshiro seed for the stub's deterministic RNG.
        public let seedHex: SeedHex

        /// Trial budget literal — `100` for `.small` (V1.42 default),
        /// `1000` for `.standard`.
        public let trialBudget: TrialBudget

        public init(
            forwardCall: String,
            inverseCall: String,
            extraImports: [String],
            carrierType: String,
            seedHex: SeedHex,
            trialBudget: TrialBudget
        ) {
            self.forwardCall = forwardCall
            self.inverseCall = inverseCall
            self.extraImports = extraImports
            self.carrierType = carrierType
            self.seedHex = seedHex
            self.trialBudget = trialBudget
        }
    }

    /// V1.42's supported carrier set. Single-element list for now; the
    /// public name keeps `expected: [String]` API-stable so v1.44
    /// (when the set widens) doesn't break the `.unsupportedCarrier`
    /// error consumer surface.
    public static let supportedCarriers: [String] = ["Complex<Double>"]

    /// Emit a round-trip verify stub. Validates the carrier first,
    /// then composes the source string.
    ///
    /// Throws `VerifyError.unsupportedCarrier(carrier:expected:)` when
    /// `inputs.carrierType` isn't in `supportedCarriers`.
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
        let defaultPass = defaultPassSection(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
        let edgePass = edgePassSection(
            forwardCall: inputs.forwardCall,
            inverseCall: inputs.inverseCall
        )
        return [header, setup, defaultPass, edgePass].joined(separator: "\n\n")
    }

    private static func headerSection(inputs: Inputs) -> String {
        """
        // V1.43.B — auto-generated two-pass round-trip verify stub.
        // Carrier: \(inputs.carrierType)
        // Forward: \(inputs.forwardCall) / Inverse: \(inputs.inverseCall)
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

    private static func defaultPassSection(forwardCall: String, inverseCall: String) -> String {
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
            let forwardResult = \(forwardCall)(value)
            let inverseResult = \(inverseCall)(forwardResult)
            if !inverseResult.isApproximatelyEqual(to: value) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(forwardResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(inverseResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// Pass 2 stub source.
    ///
    /// **`.rawStorage`-based matching.** The `matchEdgeCaseIndex`
    /// helper uses `Complex.rawStorage` (the underlying `(x, y)`
    /// tuple) rather than the public `.real` / `.imaginary` getters.
    /// swift-numerics normalizes non-finite values via the getters
    /// (any non-finite Complex reads as `.nan` on both components),
    /// which would collapse the 8 distinct non-finite curated entries
    /// (#0–#7) into one indistinguishable class. `.rawStorage`
    /// preserves the original initializer arguments so each curated
    /// entry resolves to its own index.
    private static func edgePassSection(forwardCall: String, inverseCall: String) -> String {
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

    /// Build the import block. `ComplexModule`, `RealModule`,
    /// `PropertyBased`, and `Foundation` are V1.42-mandatory.
    /// `PropertyLawComplex` is V1.43.A-mandatory — it gates the
    /// `Gen<Complex<Double>>.edgeCaseBiased()` reference that V1.43.B
    /// emits for the edge-case-biased second pass. User-supplied
    /// imports append in stable (de-duplicated, sorted) order.
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
