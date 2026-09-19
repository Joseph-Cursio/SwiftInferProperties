import Foundation
import SwiftInferCore

/// Which value a law quantifies over.
///
/// Split out of `InteractiveTriage+Accept.swift` for its length ceiling, and kept together
/// because the question is one question asked in two places: the emitter needs the carrier to
/// pick a generator, and the decline needs it to say why there is none.
extension InteractiveTriage {

    /// The type a law quantifies over: the first **parameter** for a free or static function,
    /// else the **receiver**.
    ///
    /// ## Why this is not `paramType` alone
    ///
    /// `paramType(from:)` reads the first parameter, and a nullary instance method has none —
    /// so `shellEscapeForVariableName() -> Self` was proposed and then dropped one guard from
    /// being written, even though its law is spellable: `applicationArity` for a nullary
    /// instance method is **1**, exactly what `idempotence` applies, and `call(_:)` has rendered
    /// the receiver form since #445.
    ///
    /// **Measured at 245 of 1 230 idempotence suggestions — 19.9% — across 20 corpora** (#456).
    /// One in five laws the pipeline proposed could not be written, for a missing parameter it
    /// never needed.
    ///
    /// `RoleClosureTemplate.transformedType(of:)` already drew exactly this distinction. This is
    /// the same rule, on the emitter side, where it was missing.
    static func carrierType(for evidence: Evidence) -> String? {
        if let parameter = paramType(from: evidence.signature) {
            return qualifiedAsDeclaringType(parameter, in: evidence)
        }
        // No parameter: the law is over the receiver, which is what the call is made on.
        return evidence.qualifiedTypeName
    }

    /// `typeName` spelled as a test file must spell it, when it is the declaring type itself.
    ///
    /// Inside `extension ThinkState.Mode`, a signature says `Mode` and means `ThinkState.Mode`;
    /// a test file has no such scope, so `{ (value: Mode) in … }` fails with `cannot find type
    /// 'Mode' in scope` (SwiftAssist, 2026-09-19 corpus funnel) while the generator beside it
    /// already spelled `ThinkState.Mode.normal`. Only the declaring type's own bare name is
    /// rewritten — anything else would need the lexical scope, which this does not have.
    static func qualifiedAsDeclaringType(_ typeName: String, in evidence: Evidence) -> String {
        guard let qualified = evidence.qualifiedTypeName,
              qualified.contains("."),
              qualified.split(separator: ".").last.map(String.init) == typeName
        else { return typeName }
        return qualified
    }
}
