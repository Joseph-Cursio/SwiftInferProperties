import Foundation
import SwiftInferCore

/// V1.48.B — resolves the verifier call expression for a monotonicity
/// `SemanticIndexEntry`. Single-function on a `Comparable` carrier;
/// the V1.48.A composer draws two values, sorts so `a ≤ b`, and
/// asserts `f(a) ≤ f(b)`.
///
/// **Carrier scope.** Any strategist-supported `Comparable` carrier
/// (Int / String / Bool / fixed-width ints + any user enum that
/// inherits a Comparable raw type). The strategist's surface is
/// `Comparable` by construction for raw types; for memberwise-derived
/// types (v1.49+), the comparison would require user-defined
/// `Comparable` conformance.
public enum MonotonicityPairResolver {

    /// Resolution result. Single function call expression.
    public struct Resolved: Equatable, Sendable {
        public let functionCall: String

        public init(functionCall: String) {
            self.functionCall = functionCall
        }
    }

    /// Resolve the call expression for a monotonicity entry. Errors:
    ///   - `.unsupportedTemplate` if `entry.templateName != "monotonicity"`.
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "monotonicity" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["monotonicity"]
            )
        }
        let carrier = entry.typeName ?? "(none)"
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        return Resolved(functionCall: "\(typeQualifier).\(funcName)")
    }
}
