import Foundation
import SwiftInferCore

/// V1.44.D — resolves the verifier call expression for an idempotence
/// `SemanticIndexEntry`. Single-function analog of `RoundTripPairResolver`:
/// no curated pair list, no inverse — just `entry.primaryFunctionName`
/// + the carrier type combined into a qualified call expression.
///
/// **Why simpler than RoundTripPairResolver.** Idempotence is single-
/// function (`f: T -> T`), so there's no second-half name to look up.
/// The resolver passes `primaryFunctionName` through after stripping
/// the parameter-label suffix and prepends the bare carrier name to
/// match the V1.42-era call-expression convention
/// (`<TypeName>.<funcName>`). Free-function or instance-method
/// candidates fall through to a build error inside the synthesized
/// stub, which surfaces as a `.error` outcome with the compiler message
/// — acceptable best-effort for v1.44.
///
/// **Carrier scope.** Same set as `IdempotenceStubEmitter` post-V1.44.C:
/// `Complex<Double>`, `Double`, `Int`.
public enum IdempotencePairResolver {

    /// Resolution result. Carries the single function call expression
    /// the IdempotenceStubEmitter consumes.
    public struct Resolved: Equatable, Sendable {
        public let functionCall: String

        public init(functionCall: String) {
            self.functionCall = functionCall
        }
    }

    /// Resolve the call expression for a `SemanticIndexEntry`. Errors:
    ///   - `.unsupportedTemplate` if `entry.templateName != "idempotence"`.
    ///   - `.unsupportedCarrier` if `entry.typeName` is not in
    ///     `IdempotenceStubEmitter.supportedCarriers`.
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "idempotence" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["idempotence"]
            )
        }
        let carrier = entry.typeName ?? "(none)"
        guard IdempotenceStubEmitter.supportedCarriers.contains(carrier) else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: IdempotenceStubEmitter.supportedCarriers
            )
        }
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        return Resolved(functionCall: "\(typeQualifier).\(funcName)")
    }
}
