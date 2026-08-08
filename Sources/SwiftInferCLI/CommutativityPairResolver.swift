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
        // #128 — `carrierTypeName` first: a free function has no containing type, so
        // `typeName` is nil and the `"(none)"` sentinel would be gated against
        // `supportedCarriers` as if it were a type. The operand type is the carrier for a
        // free binary operation, and the templates now record it.
        //
        // Rebind `Self` rather than taking the recorded text literally. `func merge(_
        // other: Self) -> Self` records `carrierTypeName == "Self"`, and gating that
        // against `supportedCarriers` would decline a member that resolved fine before —
        // the spelling-dependence trap `assumedCoverageSignal` already carries. This is
        // the same expression `VerifyCommand+TemplateDispatch` uses, deliberately.
        let carrier = GenericBindingResolver.bound(
            entry.carrierTypeName ?? entry.typeName ?? "(none)",
            selfType: entry.typeName
        )
        guard CommutativityStubEmitter.supportedCarriers.contains(carrier) else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: CommutativityStubEmitter.supportedCarriers
            )
        }
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        return Resolved(functionCall: CallExpressionShape.render(
            typeQualifier: typeQualifier,
            bareFunctionName: funcName
        ))
    }
}
