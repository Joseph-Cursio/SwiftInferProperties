import Foundation
import SwiftInferCore

/// V1.48.B — resolves the verifier call expression for an
/// idempotence-lifted `SemanticIndexEntry`. Single-function on a
/// lifted carrier (`[Element]`); the V1.48.A composer wraps the
/// strategist's element generator via `Generator<T>.array(of: 0...8)`
/// so the call expression here is the bare function name —
/// invoked as `funcName(xs)` and `funcName(funcName(xs))` inside the stub.
///
/// **Shape.** Like `IdempotencePairResolver` but the carrier the
/// resolver records is the *element* type — the lifted-array
/// wrapping happens in the emitter, not here. e.g. for a suggestion
/// like `Array<Int>.sorted()` with cycle-27 carrier `"Int"`, the
/// resolver returns `Array.sorted` (and the emitter renders
/// `Array.sorted(xs)`).
public enum IdempotenceLiftedPairResolver {

    /// Resolution result. Single function call expression.
    public struct Resolved: Equatable, Sendable {
        public let functionCall: String

        public init(functionCall: String) {
            self.functionCall = functionCall
        }
    }

    /// Resolve the call expression for an idempotence-lifted entry.
    /// Errors:
    ///   - `.unsupportedTemplate` if `entry.templateName != "idempotence-lifted"`.
    ///
    /// Carrier validation is intentionally absent — the V1.47.F
    /// strategist router already validates the carrier surface via
    /// `StrategistDispatchEmitter.resolveRecipe(...)`, and lifted
    /// templates accept any strategist-supported element carrier
    /// (the array-wrapping is template-side, not carrier-side).
    public static func resolve(_ entry: SemanticIndexEntry) throws -> Resolved {
        guard entry.templateName == "idempotence-lifted" else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["idempotence-lifted"]
            )
        }
        let carrier = entry.typeName ?? "(none)"
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        return Resolved(functionCall: "\(typeQualifier).\(funcName)")
    }
}
