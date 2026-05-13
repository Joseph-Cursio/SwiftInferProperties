import Foundation

/// V1.42.C.2 / V1.43.B / V1.44.B — synthesizes the standalone Swift
/// source for a round-trip verify subprocess.
///
/// **Carrier scope (V1.44.B).** Three carriers:
///
///   - `Complex<Double>`: two-pass (default finite-domain + edge-case-
///     biased via `Gen<Complex<Double>>.edgeCaseBiased()` from
///     `PropertyLawComplex`). Behavior bit-for-bit identical to v1.43.B.
///   - `Double`: two-pass — default `Double.random(in: -1e6 ... 1e6)`
///     + edge pass with an inlined `doubleWithNaN`-equivalent generator
///     (NaN at ~5% per trial). Single-entry edge-case list `[Double.nan]`,
///     so the runner's `VERIFY_EDGE_INDEX` resolves to `0` on a NaN-input
///     failure or `-1` on a finite-slice failure.
///   - `Int`: single-pass — `Gen<Int>.int(in: -bound ... bound)` with
///     `bound = 1 << (Int.bitWidth / 4)` (kit's `boundedForArithmetic`
///     convention; ~65,536 on 64-bit). Integer arithmetic has no
///     NaN/Inf semantic so the v1.43 edge pass collapses to a sentinel
///     emission of `VERIFY_EDGE_RESULT: PASS` + `VERIFY_EDGE_TRIALS: 0`
///     + `VERIFY_EDGE_SAMPLED: 0`. The V1.43.C parser still produces
///     `.bothPass(defaultTrials: N, edgeTrials: 0, edgeSampled: 0)`;
///     the renderer detects the zero-edge-pass shape and reports
///     "(integer carrier — edge pass not applicable)" in V1.44.D.
///
/// **Output shape.** Same `VERIFY_DEFAULT_*` / `VERIFY_EDGE_*` marker
/// contract as V1.43.B so `VerifyResultParser` consumes all three
/// carriers unchanged. Single-pass (Int) emits zero-edge sentinel
/// markers rather than omitting them.
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
        /// site. E.g. `"Complex.exp"` or `"abs"`. The emitter does not
        /// validate this is a syntactically-valid Swift expression; the
        /// `swift build` step in V1.42.C.3 surfaces typos as build
        /// errors.
        public let forwardCall: String

        /// Inverse-side function call. Same convention as
        /// `forwardCall`. The emitter renders
        /// `\(inverseCall)(\(forwardCall)(value))`.
        public let inverseCall: String

        /// User module(s) to import beyond the carrier-specific
        /// mandatory set. Empty entries and duplicates are filtered.
        public let extraImports: [String]

        /// Carrier type as carried on the `SemanticIndexEntry`. Must
        /// be in `supportedCarriers`; other values raise
        /// `VerifyError.unsupportedCarrier`.
        public let carrierType: String

        /// Xoshiro seed for the stub's deterministic RNG.
        public let seedHex: SeedHex

        /// Trial budget literal — `100` for `.small`, `1000` for `.standard`.
        public let trialBudget: TrialBudget

        /// V1.49.A — verbatim Swift source rendered between the
        /// imports + the `var rng = ...` line. Use for type
        /// extensions, helper functions, fixture struct definitions
        /// that the synthesized stub needs but can't import from the
        /// kit. Default `""` preserves v1.42–v1.48 emit shape.
        /// Multi-line preambles via `"""` literals are supported.
        public let preamble: String

        public init(
            forwardCall: String,
            inverseCall: String,
            extraImports: [String],
            carrierType: String,
            seedHex: SeedHex,
            trialBudget: TrialBudget,
            preamble: String = ""
        ) {
            self.forwardCall = forwardCall
            self.inverseCall = inverseCall
            self.extraImports = extraImports
            self.carrierType = carrierType
            self.seedHex = seedHex
            self.trialBudget = trialBudget
            self.preamble = preamble
        }
    }

    /// V1.44.B's supported carrier set.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit a round-trip verify stub. Validates the carrier first,
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

    /// Internal carrier discriminator — keeps the `emit` switch
    /// exhaustive and the per-composer call sites typed.
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

    private static func importsForComplexDouble(_ extra: [String]) -> String {
        let base = ["ComplexModule", "Foundation", "PropertyBased", "PropertyLawComplex", "RealModule"]
        return mergedImports(base: base, extra: extra)
    }

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
    private static func complexDefaultPassDomain(forwardCall: String) -> (String, String, String, String) {
        let bareName = forwardCall.split(separator: ".").last.map(String.init) ?? forwardCall
        switch bareName {
        case "cos", "acos", "cosh", "acosh":
            // `acos`/`acosh` principal branch returns `Re ≥ 0`, so the
            // round-trip `acos(cos(z)) == z` only holds for the right
            // half-plane.
            return ("0.0", "1.5", "-1.5", "1.5")
        default:
            // exp/log + sin/asin + tan/atan + sinh/asinh + tanh/atanh:
            // all symmetric round-trip pairs holding on `|Re| ≤ π/2`.
            return ("-1.5", "1.5", "-1.5", "1.5")
        }
    }

    private static func complexDoubleDefaultPass(forwardCall: String, inverseCall: String) -> String {
        let (reMin, reMax, imMin, imMax) = complexDefaultPassDomain(forwardCall: forwardCall)
        return """
        // --- Pass 1: default (inline finite-domain) ---
        //
        // V1.55.A — per-function default-pass domain. Cycle-52 evidence
        // (`docs/calibration-cycle-52-findings.md`) showed the round-trip
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
                    Double.random(in: \(reMin) ... \(reMax)),
                    Double.random(in: \(imMin) ... \(imMax))
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

// V1.44.B shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
extension RoundTripStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.44.B — auto-generated round-trip verify stub.
        // Carrier: \(inputs.carrierType)
        // Forward: \(inputs.forwardCall) / Inverse: \(inputs.inverseCall)
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
