import PropertyLawCore
import SwiftInferCore

/// `identityElement` and `inversePair`, lifted out of `LiftedTestEmitter.swift` when the
/// `call:` threading for #415 took that file past SwiftLint's 400-line cap. Same convention as
/// the `+M5` / `+Replay` / `+Regression` overflow files beside it; no behaviour change from
/// the move.
extension LiftedTestEmitter {

    /// Emit an identity-element test stub for `f: (T, T) -> T` paired
    /// with a static identity element `T.\(identityName)`. The body
    /// draws a single `T` value and asserts both
    /// `f(value, T.identity) == value` and `f(T.identity, value) == value`.
    /// `identityName` is the bare member name on `typeName` (e.g.
    /// `"empty"`, `"zero"`, `"identity"`), extracted from the
    /// suggestion's evidence[1] displayName (`"\(typeName).\(identityName)"`)
    /// at dispatch time. M8.2 — retires the "no stub writeout available
    /// for template 'identity-element' in v1" diagnostic.
    public static func identityElement(
        funcName: String,
        typeName: String,
        identityName: String,
        seed: SamplingSeed.Value,
        generator: String,
        call: String? = nil
    ) -> String {
        let callee = call ?? funcName
        let testFunctionName = "\(funcName)_hasIdentity_\(identityName)"
        // Single-value sample — the identity is constant in the body
        // (referenced via `\(typeName).\(identityName)`), so the
        // canonical `{ rng in (generator).run(using: &rng) }` shape applies.
        let property = "\(callee)(value, \(typeName).\(identityName)) == value"
            + " && \(callee)(\(typeName).\(identityName), value) == value"
        let failureLabel = "\(funcName)(_:_:) failed identity-element \(typeName).\(identityName)"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit an inverse-pair test stub. Body shape matches `roundTrip`
    /// (`inverse(forward(value)) == value`); distinct test-function
    /// name + failure label keep the two arms disambiguable in test
    /// runner output. The non-Equatable caveat lives in the §4.5
    /// explainability block surfaced before accept.
    public static func inversePair(
        forwardName: String,
        inverseName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict,
        forwardCall: String? = nil,
        inverseCall: String? = nil
    ) -> String {
        _ = typeName
        let forwardCallee = forwardCall ?? forwardName
        let inverseCallee = inverseCall ?? inverseName
        let testFunctionName = "\(forwardName)_\(inverseName)_inversePair"
        let property = equalityExpression(
            lhs: "\(inverseCallee)(\(forwardCallee)(value))",
            rhs: "value",
            kind: equalityKind
        )
        let failureLabel = "\(forwardName)/\(inverseName) inverse-pair failed"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }
}
