import SwiftInferCore

/// Binary-op `(T, T) -> T` paired with a unary inverse function
/// `(T) -> T` named like an inverse on the same type `T`. Consumed by
/// M8.4's `RefactorBridgeOrchestrator` to score the **Group** claim per
/// PRD v0.4 §5.4 — Group requires Monoid (associativity + identity)
/// plus an inverse witness.
///
/// `InverseElementPair` is the Group analogue of `IdentityElementPair`:
/// where IdentityElementPair pairs a binary op with a static identity
/// constant (`T.empty`), this pairs a binary op with a unary inverse
/// function (`T.negate(_:)` etc.). M8.3 is the pairing pass; M8.4 is the
/// orchestrator that promotes the (Monoid + inverse) signal set to a
/// `Group` proposal.
public struct InverseElementPair: Sendable, Equatable {

    public let operation: FunctionSummary
    public let inverse: FunctionSummary

    public init(operation: FunctionSummary, inverse: FunctionSummary) {
        self.operation = operation
        self.inverse = inverse
    }
}

/// Type- and naming-driven pair finder for the inverse-element signal.
/// Mirrors `IdentityElementPairing`'s shape with two adjustments:
///
/// - **Naming is a pre-filter, not a signal.** A unary `T -> T`
///   function without an inverse-shaped name (`negate`, `inverted`,
///   `reciprocal`, …) doesn't surface as a candidate — the structural
///   signal alone is too weak (a `T -> T` could be idempotent, monotonic,
///   or just a transform). Confining to curated + project-vocabulary
///   names matches PRD §5.4's "inverse function" requirement for the
///   Group claim.
/// - **No standalone Suggestion.** This pass produces witness records
///   M8.4's orchestrator consumes; the user never sees an "inverse-element"
///   suggestion in `discover` output. Group claims surface via the
///   per-type RefactorBridge proposal pipeline.
///
/// Module scope is the entire scanned corpus (matching `FunctionPairing`
/// + `IdentityElementPairing`).
public enum InverseElementPairing {

    /// Curated unary inverse names. PRD v0.2 §5.2 priority-1 list for
    /// the inverse signal. The shipped list covers the natural
    /// algebraic-inverse names (`negate`, `inverse`, `reciprocal`)
    /// plus the lattice-theoretic complement and the geometry-shaped
    /// `invert` / `inverted`. Project-vocabulary `inverseElementVerbs`
    /// (PRD §4.5) extends this set without modifying the source.
    public static let curatedInverseVerbs: Set<String> = [
        "negate",
        "negated",
        "inverse",
        "inverted",
        "reciprocal",
        "complement",
        "invert"
    ]

    /// Every pair `(operation, inverse)` such that
    ///   - `operation` is a binary op `(T, T) -> T` (same shape as
    ///     commutativity / associativity / identity-element: 2 same-type
    ///     non-`inout` params, non-`mutating`, return type matches
    ///     param type, non-`Void`),
    ///   - `inverse` is a unary `(T) -> T` (one non-`inout` param,
    ///     non-`mutating`, return type matches param type, non-`Void`),
    ///   - `inverse.name` is in `curatedInverseVerbs` or
    ///     `vocabulary.inverseElementVerbs`.
    /// Pairs are returned sorted by `(operation.file, operation.line,
    /// inverse.file, inverse.line)` so the list is deterministic.
    ///
    /// The same `inverse` may pair with multiple `operation`s if the
    /// corpus declares more than one binary op on the same type — every
    /// `(operation, inverse)` combination surfaces, mirroring
    /// `IdentityElementPairing`'s "one pair per (op, identity)" rule.
    public static func candidates(
        in summaries: [FunctionSummary],
        vocabulary: Vocabulary = .empty
    ) -> [InverseElementPair] {
        let inverseNames = curatedInverseVerbs.union(vocabulary.inverseElementVerbs)
        let pairableOps = summaries.filter(isBinaryOp)
        let inverseCandidates = summaries.filter { isUnaryInverse(of: $0, named: inverseNames) }
        var pairs: [InverseElementPair] = []
        for operation in pairableOps {
            guard let opType = binaryOpType(of: operation) else {
                continue
            }
            for inverse in inverseCandidates where unaryType(of: inverse) == opType {
                pairs.append(InverseElementPair(operation: operation, inverse: inverse))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    // MARK: - Filters

    /// Same `(T, T) -> T` shape `IdentityElementPairing` uses. Kept
    /// duplicated rather than calling across modules so M8.3 stays a
    /// pure additive change to `SwiftInferTemplates`.
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

    /// Unary `T -> T` with a curated/vocabulary inverse name. Filters
    /// out `mutating`, `inout`, `Void`-returning, and renamed-arg
    /// shapes the algebraic-inverse semantics doesn't fit.
    private static func isUnaryInverse(
        of summary: FunctionSummary,
        named inverseNames: Set<String>
    ) -> Bool {
        guard inverseNames.contains(summary.name),
              summary.parameters.count == 1,
              !summary.isMutating else {
            return false
        }
        let param = summary.parameters[0]
        guard !param.isInout,
              let returnType = summary.returnTypeText,
              returnType == param.typeText,
              returnType != "Void",
              returnType != "()" else {
            return false
        }
        return true
    }

    private static func binaryOpType(of summary: FunctionSummary) -> String? {
        summary.returnTypeText
    }

    private static func unaryType(of summary: FunctionSummary) -> String? {
        summary.returnTypeText
    }

    private static func lessThan(
        _ lhs: InverseElementPair,
        _ rhs: InverseElementPair
    ) -> Bool {
        if lhs.operation.location.file != rhs.operation.location.file {
            return lhs.operation.location.file < rhs.operation.location.file
        }
        if lhs.operation.location.line != rhs.operation.location.line {
            return lhs.operation.location.line < rhs.operation.location.line
        }
        if lhs.inverse.location.file != rhs.inverse.location.file {
            return lhs.inverse.location.file < rhs.inverse.location.file
        }
        return lhs.inverse.location.line < rhs.inverse.location.line
    }
}
