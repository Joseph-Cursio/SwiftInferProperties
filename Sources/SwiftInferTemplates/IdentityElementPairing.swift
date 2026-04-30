import SwiftInferCore

/// Binary-op `(T, T) -> T` paired with a static identity candidate of the
/// same type `T`. Consumed by `IdentityElementTemplate` to score the
/// "monoid candidate" claim per PRD v0.3 §5.2.
///
/// Pairs are oriented by `(file, line)` of the operation summary so output
/// is byte-stable — `IdentityCandidate.location` is rendered alongside in
/// the explainability block but the *primary* anchor is always the op,
/// matching how a developer searches for the function definition first.
public struct IdentityElementPair: Sendable, Equatable {

    public let operation: FunctionSummary
    public let identity: IdentityCandidate

    public init(operation: FunctionSummary, identity: IdentityCandidate) {
        self.operation = operation
        self.identity = identity
    }
}

/// Type-driven pair finder for the identity-element template. Mirrors
/// `FunctionPairing`'s M1.4 type-filter approach — naming and explicit
/// `@Discoverable` filters live in the per-template scorer; the pairer
/// only enforces the necessary `(T, T) -> T` + `let X: T` shape.
///
/// Module scope is the entire scanned corpus (matching `FunctionPairing`).
/// Per PRD §5.5's tiered filter, naming is a signal — not a pre-filter —
/// so a `(T, T) -> T` op + `T.empty` constant always reaches the scorer
/// even when the op's name isn't in the curated commutativity verb list.
public enum IdentityElementPairing {

    /// Every candidate pair `(operation, identity)` such that
    ///   - `operation` is a binary op `(T, T) -> T` (same shape as
    ///     commutativity / associativity: 2 same-type non-`inout` params,
    ///     non-`mutating`, return type matches param type, non-`Void`),
    ///   - `identity.typeText == T`.
    /// Pairs are returned sorted by `(operation.file, operation.line,
    /// identity.file, identity.line)` so the list is deterministic.
    public static func candidates(
        in summaries: [FunctionSummary],
        identities: [IdentityCandidate]
    ) -> [IdentityElementPair] {
        let pairableOps = summaries.filter(isBinaryOp)
        var pairs: [IdentityElementPair] = []
        for operation in pairableOps {
            guard let typeText = binaryOpType(of: operation) else {
                continue
            }
            for identity in identities where identity.typeText == typeText {
                pairs.append(IdentityElementPair(operation: operation, identity: identity))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    private static func isBinaryOp(_ summary: FunctionSummary) -> Bool {
        guard summary.parameters.count == 2,
              !summary.isMutating else {
            return false
        }
        let first = summary.parameters[0]
        let second = summary.parameters[1]
        guard !first.isInout,
              !second.isInout,
              first.typeText == second.typeText,
              let returnType = summary.returnTypeText,
              returnType == first.typeText,
              returnType != "Void",
              returnType != "()" else {
            return false
        }
        return true
    }

    private static func binaryOpType(of summary: FunctionSummary) -> String? {
        summary.returnTypeText
    }

    private static func lessThan(
        _ lhs: IdentityElementPair,
        _ rhs: IdentityElementPair
    ) -> Bool {
        if lhs.operation.location.file != rhs.operation.location.file {
            return lhs.operation.location.file < rhs.operation.location.file
        }
        if lhs.operation.location.line != rhs.operation.location.line {
            return lhs.operation.location.line < rhs.operation.location.line
        }
        if lhs.identity.location.file != rhs.identity.location.file {
            return lhs.identity.location.file < rhs.identity.location.file
        }
        return lhs.identity.location.line < rhs.identity.location.line
    }
}
