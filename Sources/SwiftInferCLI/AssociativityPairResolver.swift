import Foundation
import SwiftInferCore

/// V1.46.B — resolves the verifier call expression for an associativity
/// `SemanticIndexEntry`. Single-function three-argument analog of
/// `CommutativityPairResolver`.
///
/// **Shape.** Associativity is single-function (`f: (T, T) -> T`), so
/// there's no curated pair list; the resolver produces the qualified
/// call expression `<bareCarrier>.<funcName>` that the stub then
/// invokes as `<funcName>(<funcName>(a, b), c)` and
/// `<funcName>(a, <funcName>(b, c))`. Free-function or instance-method
/// candidates fall through to a build error inside the synthesized
/// stub (acceptable best-effort).
///
/// **Carrier scope.** Same set as `AssociativityStubEmitter`:
/// `Complex<Double>`, `Double`, `Int`.
public enum AssociativityPairResolver {

    /// Resolution result. Carries the single function call expression
    /// the `AssociativityStubEmitter` consumes.
    public struct Resolved: Equatable, Sendable {
        public let functionCall: String

        public init(functionCall: String) {
            self.functionCall = functionCall
        }
    }

    /// Resolve the call expression for a `SemanticIndexEntry`. Errors:
    ///   - `.unsupportedTemplate` if `entry.templateName != "associativity"`.
    ///   - `.unsupportedCarrier` if `entry.typeName` is not in
    ///     `AssociativityStubEmitter.supportedCarriers`.
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "associativity" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["associativity"]
            )
        }
        let carrier = entry.typeName ?? "(none)"
        guard AssociativityStubEmitter.supportedCarriers.contains(carrier) else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: AssociativityStubEmitter.supportedCarriers
            )
        }
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        return Resolved(functionCall: "\(typeQualifier).\(funcName)")
    }
}
