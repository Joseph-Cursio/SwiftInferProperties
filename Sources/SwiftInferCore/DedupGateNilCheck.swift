import SwiftSyntax

/// The pre-fetched **nil-check** dedup shape (M12), split from `DedupGateShape.swift`
/// (at the file-length cap).
///
/// `if <fetchedOptional> != nil { return }` — fetch a row, and if it already exists,
/// early-return a no-op (wallet's `if r != nil { return .ok }` in the pass/order
/// registration routes). It is the `!= nil`-comparison sibling of the `if let`
/// pre-fetched form the M3 reader already handles.
///
/// **The name must be fetch-bound.** That is what separates a dedup from an
/// error-classification of the same syntax: FeatherCMS writes
/// `if beginError != nil { return "Begin" }`, but `beginError` is a caught error, not
/// a fetched row, so it is absent from `fetchedNames` and does not match.
extension DedupGateClassifier {

    /// Whether `expr` is `<fetchedName> != nil` (in either operand order).
    static func isFetchedNilCheck(_ expr: ExprSyntax, fetchedNames: Set<String>) -> Bool {
        guard let sequence = expr.as(SequenceExprSyntax.self) else { return false }
        let elements = Array(sequence.elements)
        let comparesNotEqual = elements.contains {
            $0.as(BinaryOperatorExprSyntax.self)?.operator.text == "!="
        }
        let hasNil = elements.contains { $0.is(NilLiteralExprSyntax.self) }
        let hasFetchedName = elements.contains { element in
            guard let reference = element.as(DeclReferenceExprSyntax.self) else { return false }
            return fetchedNames.contains(reference.baseName.text)
        }
        return comparesNotEqual && hasNil && hasFetchedName
    }
}
