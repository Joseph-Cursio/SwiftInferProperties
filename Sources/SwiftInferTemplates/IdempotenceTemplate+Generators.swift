import Foundation
import SwiftInferCore

// Collision-biased generator recipes for the idempotence carrier `T` (the return
// type in `T -> T` / `T? -> T`).
//
// Scoped to String-COLLECTION carriers (`[String]` / `Array<String>`), where the
// idempotence collision is precisely "an element repeats / is already present" —
// exactly what `mergedWith` and `deindent` turn on. A scalar `String` gets none:
// `CollisionBias.collidingString` is path-flavored (a *predicate* collision), and
// emitting it here would be cargo-culting the wrong collision. `Int -> Int` and
// other carriers get none for the same reason PredicateTemplate ships only String
// recipes — a small alphabet only helps where structure collides.
extension IdempotenceTemplate {

    static func makeGenerators(for summary: FunctionSummary) -> [GeneratorRecipe] {
        guard let carrier = summary.returnTypeText else { return [] }
        let trimmed = carrier.trimmingCharacters(in: .whitespaces)
        guard isStringArray(trimmed) else { return [] }
        let subject = summary.parameters.first?.internalName ?? "value"
        return [CollisionBias.collidingStringArray(subject: subject, typeName: trimmed)]
    }

    private static func isStringArray(_ type: String) -> Bool {
        type == "[String]" || type == "Array<String>"
    }
}
