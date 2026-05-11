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
/// **Generator choice in V1.42.** The emitted stub uses an inline
/// finite-domain generator (`Double.random(in: -1e6 ... 1e6)` for each
/// component). V1.43 swaps this for
/// `Gen<Complex<Double>>.edgeCaseBiased()` from `PropertyLawComplex` —
/// the swap is one-line per the v1.42 plan §"Why default-pass only".
///
/// **Output shape.** The stub:
///   1. Reads `Xoshiro` from a hardcoded seed.
///   2. Loops for `trialBudget` trials, sampling a `Complex<Double>`
///      per trial.
///   3. Computes `inverse(forward(value))` and compares to `value` via
///      `isApproximatelyEqual(to:)` (IEEE 754 rounding makes `==`
///      unsuitable for FP).
///   4. On counterexample: prints `VERIFY_RESULT: FAIL` + the
///      trial / input / forward / inverse / expected, exits 1.
///   5. On clean pass: prints `VERIFY_RESULT: PASS` + the trial count,
///      exits 0.
///
/// V1.42.C.4 parses the `VERIFY_*` lines to render the user-facing
/// result.
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
        let seedLine = """
            var rng: any SeededRandomNumberGenerator = Xoshiro(seed: (
                0x\(hex(inputs.seedHex.stateA)),
                0x\(hex(inputs.seedHex.stateB)),
                0x\(hex(inputs.seedHex.stateC)),
                0x\(hex(inputs.seedHex.stateD))
            ))
            """
        return """
        // V1.42.C.2 — auto-generated round-trip verify stub.
        // Carrier: \(inputs.carrierType)
        // Forward: \(inputs.forwardCall) / Inverse: \(inputs.inverseCall)
        // Generator: inline finite-domain (Double.random in ±1e6);
        // V1.43 swaps to Gen<Complex<Double>>.edgeCaseBiased() for the
        // two-pass design.

        \(importsBlock)

        \(seedLine)

        let trials = \(trials)
        let generator: Generator<Complex<Double>, some SendableSequenceType> =
            Gen<Int>.int(in: 0 ..< 1).map { _ in
                Complex(
                    Double.random(in: -1_000_000.0 ... 1_000_000.0),
                    Double.random(in: -1_000_000.0 ... 1_000_000.0)
                )
            }

        for trial in 0 ..< trials {
            let value = generator.run(using: &rng)
            let forwardResult = \(inputs.forwardCall)(value)
            let inverseResult = \(inputs.inverseCall)(forwardResult)
            if !inverseResult.isApproximatelyEqual(to: value) {
                print("VERIFY_RESULT: FAIL")
                print("VERIFY_TRIAL: \\(trial)")
                print("VERIFY_INPUT: \\(value)")
                print("VERIFY_FORWARD: \\(forwardResult)")
                print("VERIFY_INVERSE: \\(inverseResult)")
                exit(1)
            }
        }

        print("VERIFY_RESULT: PASS")
        print("VERIFY_TRIALS: \\(trials)")
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
