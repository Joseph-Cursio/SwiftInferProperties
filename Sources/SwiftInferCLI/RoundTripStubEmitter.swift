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
///     the V1.153 "no edge pass ran for this carrier" line.
///
/// **Output shape.** Same `VERIFY_DEFAULT_*` / `VERIFY_EDGE_*` marker
/// contract as V1.43.B so `VerifyResultParser` consumes all three
/// carriers unchanged. Single-pass (Int) emits zero-edge sentinel
/// markers rather than omitting them.
///
/// V1.43.C/D parse the `VERIFY_*` lines and render the 4-outcome table
/// (`bothPass` / `edgeCaseAdvisory` / `defaultFails` / `error`).
public enum RoundTripStubEmitter: SeededStubEmitter {

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
            case .standard: return 1_000
            }
        }
    }

    /// Inputs to the emitter — collected into a struct rather than a
    /// long parameter list so the call sites stay readable and the
    /// `function_parameter_count` lint rule doesn't fire.
    public struct Inputs: Equatable, Sendable, CarrierStubInputs {
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
        try CarrierStubDispatch.emit(
            inputs,
            supportedCarriers: supportedCarriers,
            complexDouble: composeComplexDoubleSource,
            double: composeDoubleSource,
            int: composeIntSource
        )
    }
}
