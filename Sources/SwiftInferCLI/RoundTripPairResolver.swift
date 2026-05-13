import Foundation
import SwiftInferCore

/// V1.42.C.6 — resolves the inverse-side function name + the verifier
/// call expressions for a round-trip `SemanticIndexEntry`.
///
/// **Why this exists.** `SemanticIndexEntry` (v1.33) stores only the
/// forward side of a round-trip pair in `primaryFunctionName`. To
/// synthesize the verify stub we need *both* halves. v1.42 ships a
/// **curated lookup table**: a small set of well-known round-trip
/// pairs (Complex's `exp/log`, `cos/acos`, `sin/asin`, `tan/atan` plus
/// their hyperbolic siblings). Suggestions outside the curated list
/// error with `.unsupportedPair`, pointing the user at the v1.43+
/// roadmap.
///
/// **Why curated, not derived from Evidence.** The full
/// `Suggestion.evidence: [Evidence]` array carries both names, but
/// the verify pipeline currently reads only the persisted
/// SemanticIndex (no fresh discover pass). A future cycle could store
/// both halves in the index (schema bump) or rerun discover for the
/// matched entry — both deferred past v1.42.
///
/// **Carrier scope.** v1.42 supports `Complex<Double>` only. The pair
/// list keys on the *bare* function name (e.g. `"exp(_:)"`); the
/// emitter prepends `Complex.` for the qualified call expression
/// since the carrier type `Complex<Double>` resolves to the
/// `Complex` static method namespace (the `<Double>` argument is
/// inferred from the call site).
public enum RoundTripPairResolver {

    /// Curated round-trip pair. Both directions are entered
    /// independently (`exp/log` and `log/exp`) so the resolver can
    /// look up either side as the forward.
    public struct Pair: Equatable, Sendable {
        public let forwardName: String
        public let inverseName: String
    }

    /// V1.42 curated set + V1.45.D hyperbolic expansion. 7
    /// bidirectional pairs = 14 entries. Cycle-41 findings (`docs/
    /// calibration-cycle-41-findings.md`) flagged the hyperbolic
    /// pairs as low-effort high-coverage additions — picks #4
    /// (`sinh/asinh`) and #5 (`tanh/atanh`) on the cycle-27 corpus
    /// land in-scope after this expansion.
    public static let curated: [Pair] = [
        Pair(forwardName: "exp(_:)", inverseName: "log(_:)"),
        Pair(forwardName: "log(_:)", inverseName: "exp(_:)"),
        Pair(forwardName: "cos(_:)", inverseName: "acos(_:)"),
        Pair(forwardName: "acos(_:)", inverseName: "cos(_:)"),
        Pair(forwardName: "sin(_:)", inverseName: "asin(_:)"),
        Pair(forwardName: "asin(_:)", inverseName: "sin(_:)"),
        Pair(forwardName: "tan(_:)", inverseName: "atan(_:)"),
        Pair(forwardName: "atan(_:)", inverseName: "tan(_:)"),
        // V1.45.D hyperbolic additions.
        Pair(forwardName: "sinh(_:)", inverseName: "asinh(_:)"),
        Pair(forwardName: "asinh(_:)", inverseName: "sinh(_:)"),
        Pair(forwardName: "cosh(_:)", inverseName: "acosh(_:)"),
        Pair(forwardName: "acosh(_:)", inverseName: "cosh(_:)"),
        Pair(forwardName: "tanh(_:)", inverseName: "atanh(_:)"),
        Pair(forwardName: "atanh(_:)", inverseName: "tanh(_:)")
    ]

    /// Resolution result. Carries the inverse name + the qualified
    /// call expressions the C.2 emitter consumes.
    public struct Resolved: Equatable, Sendable {
        public let forwardCall: String
        public let inverseCall: String

        public init(forwardCall: String, inverseCall: String) {
            self.forwardCall = forwardCall
            self.inverseCall = inverseCall
        }
    }

    /// Resolve the pair for a `SemanticIndexEntry`. Errors:
    ///   - `.unsupportedTemplate` if `entry.templateName` is not
    ///     `"round-trip"` (v1.42 only verifies round-trip suggestions).
    ///   - `.unsupportedCarrier` if `entry.typeName` is not in
    ///     `RoundTripStubEmitter.supportedCarriers` — v1.42 supports
    ///     `Complex<Double>` only.
    ///   - `.unsupportedPair` if `entry.primaryFunctionName` is not
    ///     in the curated list.
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "round-trip" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["round-trip"]
            )
        }
        let carrier = entry.typeName ?? "(none)"
        guard RoundTripStubEmitter.supportedCarriers.contains(carrier) else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: RoundTripStubEmitter.supportedCarriers
            )
        }
        let forwardBare = entry.primaryFunctionName
        let typeQualifier = bareTypeName(from: carrier)
        // V1.49.C.3 — first try the curated pair lookup; on miss,
        // fall back to the entry's secondaryFunctionName (populated
        // discover-side from the round-trip suggestion's evidence[1]).
        // The .unsupportedPair error fires only when both lookups fail.
        if let pair = curated.first(where: { $0.forwardName == forwardBare }) {
            return Resolved(
                forwardCall: CallExpressionShape.render(
                    typeQualifier: typeQualifier,
                    bareFunctionName: stripParameterLabels(pair.forwardName)
                ),
                inverseCall: CallExpressionShape.render(
                    typeQualifier: typeQualifier,
                    bareFunctionName: stripParameterLabels(pair.inverseName)
                )
            )
        }
        if let inverseBare = entry.secondaryFunctionName {
            return Resolved(
                forwardCall: CallExpressionShape.render(
                    typeQualifier: typeQualifier,
                    bareFunctionName: stripParameterLabels(forwardBare)
                ),
                inverseCall: CallExpressionShape.render(
                    typeQualifier: typeQualifier,
                    bareFunctionName: stripParameterLabels(inverseBare)
                )
            )
        }
        throw VerifyError.unsupportedPair(
            forward: forwardBare,
            supported: curated.map(\.forwardName)
        )
    }

    /// `"Complex<Double>"` → `"Complex"`. Strips the generic argument
    /// so the static-method call shape is `Complex.exp(value)`
    /// (Swift infers `<Double>` from the argument's type).
    static func bareTypeName(from typeName: String) -> String {
        if let openAngle = typeName.firstIndex(of: "<") {
            return String(typeName[..<openAngle])
        }
        return typeName
    }

    /// `"exp(_:)"` → `"exp"`. The C.2 stub appends `(value)` /
    /// `(forwardResult)` itself, so we drop the parameter-label
    /// suffix from the curated entry.
    static func stripParameterLabels(_ functionName: String) -> String {
        if let openParen = functionName.firstIndex(of: "(") {
            return String(functionName[..<openParen])
        }
        return functionName
    }
}
