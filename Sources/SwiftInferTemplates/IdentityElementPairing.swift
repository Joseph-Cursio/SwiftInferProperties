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
    ///   - `identity.typeText == T`,
    ///   - the (`identity.name`, `operation.name`) pair is *not* a known
    ///     mismatch per `skipsKnownMismatched(...)`.
    /// Pairs are returned sorted by `(operation.file, operation.line,
    /// identity.file, identity.line)` so the list is deterministic.
    ///
    /// V1.6.1 — added the (constant, op) skip-list filter as the
    /// *complementary* mechanism to v1.5's coverage veto. v1.5 suppresses
    /// pairs the kit already verifies; v1.6 suppresses cross-product
    /// pairs whose constant is in the kit-blessed set
    /// (`zero` / `one` / `empty` / `identity`) but whose op-name doesn't
    /// bind to a kit-published identity law (e.g. `(zero, *)`,
    /// `(zero, /)`, `(one, +)`). Combined with v1.5, ComplexModule's
    /// 6 cycle-1 identity-element hits → 0 surfaced suggestions.
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
                if skipsKnownMismatched(
                    identityName: identity.name,
                    opName: operation.name
                ) {
                    continue
                }
                pairs.append(IdentityElementPair(operation: operation, identity: identity))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    /// V1.6.1 — kit-blessed identity-constant names whose pairing with
    /// a stdlib-operator op-name *should* map to a known kit-published
    /// identity law via
    /// `IdentityElementTemplate.identityCoverageCandidate(...)`.
    /// Constants outside this set (e.g. `none`, `default`, custom user
    /// names) are passed through unfiltered — pair-formation defers to
    /// the existing type-shape gate and v1.5's coverage veto downstream.
    ///
    /// Skip-list rather than allow-list (v1.6 plan open decision #1):
    /// filter only pairs whose constant is *known* and whose op is a
    /// *known mismatched stdlib operator*; preserve recall for
    /// unrecognized constants and user-named ops the engine doesn't yet
    /// model.
    private static let kitBlessedIdentityConstants: Set<String> = [
        "zero", "one", "empty", "identity"
    ]

    /// V1.6.1 — stdlib binary operators whose identity laws PropertyLawKit
    /// publishes (kit binds `.zero` to `+`, `.one` to `*`). When the op
    /// is in this set, a (kit-blessed-constant, op) combo not in V1.5.2's
    /// mapping is a known cross-product mismatch worth filtering.
    /// User-named ops (`merge`, `combine`, `intersect`, etc.) fall
    /// outside this set — pair-formation defers to v1.5's coverage veto
    /// downstream rather than filtering syntactically.
    ///
    /// Limited to the five arithmetic operators that have published
    /// identity laws on `Numeric` / `AdditiveArithmetic`, plus the
    /// curated math-library names `pow` and `**` (V1.6.1 maintenance
    /// patch — closes the cycle-3 ComplexModule survivor `(zero, pow)`).
    /// Bitwise (`&`, `|`, `^`) and shift (`<<`, `>>`) operators are
    /// excluded — they have identity laws on `BinaryInteger` but the
    /// kit doesn't yet model `BinaryInteger`-specific laws separately.
    ///
    /// **`pow` rationale:** `pow(x, 0) == 1` (not `x`), so `(zero, pow)`
    /// is structurally the same kind of cross-product mismatch as
    /// `(zero, *)` — `.zero` is not pow's identity. The risk a user
    /// defines `pow` with monoid-style identity semantics is small;
    /// they would not name such an op `pow` (the math convention is
    /// well-established). `**` is the curated alternative spelling.
    private static let stdlibBinaryOperators: Set<String> = [
        "+", "-", "*", "/", "%", "pow", "**"
    ]

    /// V1.6.1 — returns `true` when the pair-formation layer should
    /// drop this `(identityName, opName)` combination as a known
    /// cross-product mismatch. Fires when *all three* of:
    ///
    /// - `identityName` is in `kitBlessedIdentityConstants` (the engine
    ///   recognizes the constant as a kit-monoid-style identity),
    /// - `opName` is in `stdlibBinaryOperators` (the kit publishes
    ///   identity laws for this operator),
    /// - `IdentityElementTemplate.identityCoverageCandidate(...)`
    ///   returns `nil` for the (name, op) pair (no kit-published
    ///   identity law matches this specific combination).
    ///
    /// Examples that get skipped: `(zero, *)`, `(zero, /)`, `(zero, -)`,
    /// `(zero, %)`, `(one, +)`, `(one, -)`, `(empty, *)`, `(empty, -)`.
    /// Examples that pass through: `(zero, +)` (kit-blessed combo →
    /// emit; v1.5 veto handles the AdditiveArithmetic-covered subset),
    /// `(zero, merge)` (user-named op → emit), `(zero, pow)` (user-named
    /// op → emit; cycle-1 noise survives, but cycle-3 leaves it for a
    /// future curated-op-list extension), `(none, +)` (constant not in
    /// kit-blessed set → emit), `(neutral, combine)` (custom user
    /// constant → emit).
    private static func skipsKnownMismatched(
        identityName: String,
        opName: String
    ) -> Bool {
        guard kitBlessedIdentityConstants.contains(identityName),
              stdlibBinaryOperators.contains(opName) else {
            return false
        }
        return IdentityElementTemplate.identityCoverageCandidate(
            identityName: identityName,
            opName: opName
        ) == nil
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
