import Foundation
import SwiftInferCore

/// V1.45.B — resolves the verifier call expression for a commutativity
/// `SemanticIndexEntry`. Single-function two-argument analog of
/// `IdempotencePairResolver` (which is itself the single-function
/// analog of `RoundTripPairResolver`).
///
/// **Shape.** Commutativity is single-function (`f: (T, T) -> T`), so
/// there's no curated pair list; the resolver just produces the
/// qualified call expression `<bareCarrier>.<funcName>` that the
/// stub then invokes as `<funcName>(lhs, rhs)` and `<funcName>(rhs, lhs)`.
/// Free-function or instance-method candidates fall through to a
/// build error inside the synthesized stub (acceptable best-effort).
///
/// **Carrier scope.** Same set as `CommutativityStubEmitter`:
/// `Complex<Double>`, `Double`, `Int`.
public enum CommutativityPairResolver {

    /// Resolution result. Carries the single function call expression
    /// the CommutativityStubEmitter consumes.
    public struct Resolved: Equatable, Sendable {
        public let functionCall: String

        public init(functionCall: String) {
            self.functionCall = functionCall
        }
    }

    /// Resolve the call expression for a `SemanticIndexEntry`. Errors:
    ///   - `.unsupportedTemplate` if `entry.templateName != "commutativity"`.
    ///   - `.unsupportedCarrier` if `entry.typeName` is not in
    ///     `CommutativityStubEmitter.supportedCarriers`.
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "commutativity" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["commutativity"]
            )
        }
        let carrier = entry.typeName ?? "(none)"
        guard CommutativityStubEmitter.supportedCarriers.contains(carrier) else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: CommutativityStubEmitter.supportedCarriers
            )
        }
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        return Resolved(functionCall: "\(typeQualifier).\(funcName)")
    }
}
