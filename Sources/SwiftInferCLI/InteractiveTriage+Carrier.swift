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
        if let parameter = paramType(from: evidence.signature) { return parameter }
        // No parameter: the law is over the receiver, which is what the call is made on.
        return evidence.qualifiedTypeName
    }
}
