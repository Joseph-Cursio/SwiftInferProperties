import SwiftInferCore

/// The **binary-idempotence** law: `op(x, x) == x` — combining a value with
/// itself is a no-op.
///
/// This is the idempotent leg of a **semilattice**. The catalogue already has
/// the other two legs as `(T, T) -> T` templates — `CommutativityTemplate`
/// (`op(a, b) == op(b, a)`) and `AssociativityTemplate`
/// (`op(op(a, b), c) == op(a, op(b, c))`) — so a `min` / `max` / `union` /
/// `intersection` surfaces all three, and together they say "this is a
/// semilattice." This template is the missing third leg; without it the engine
/// could call `union` commutative and associative but never idempotent, which is
/// the one law that separates a join/meet from an ordinary associative op.
///
/// **A curated name is required to fire.** Idempotence is a *rare* property of a
/// binary operator — `+`, `*`, and concatenation all fail it (`x + x == x` only
/// at zero) — so firing on the `(T, T) -> T` shape alone would be almost all
/// false positives, the Daikon flood the catalogue exists to avoid. Only the
/// canonical join/meet verbs (`min`, `max`, `union`, `intersection`, `gcd`,
/// `lcm`, `meet`) get the law; everything else stays silent.
///
/// **Refutable:** a `max` with a `<`/`>` mix-up, a `union` that appends instead
/// of unions (so `union(x, x)` doubles), a `gcd` off by a factor — each fails
/// `op(x, x) == x`, and none is caught by an example test that only checks
/// distinct operands.
public enum BinaryIdempotenceTemplate {

    /// Canonical join/meet verbs — binary operators for which `op(x, x) == x`.
    /// Deliberately conservative: `merge` / `combine` are excluded (they usually
    /// ADD, so `merge(x, x)` doubles), and `join` is excluded (it collides with
    /// string concatenation, which is not idempotent). Additive verbs live in
    /// `CommutativityTemplate.curatedVerbs`, not here.
    public static let curatedVerbs: Set<String> = [
        "min", "max", "minimum", "maximum",
        "union", "intersection", "intersect",
        "gcd", "lcm",
        "meet"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "binary-idempotence",
            appliesTo: Self.isSemilatticeOp,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.containingTypeName },
            // The operand type `T` — `binaryOperatorTypeSymmetrySignal` only
            // fires when both parameters and the return type are `T`, so the
            // return type is `T` and is always present here.
            carrierType: { $0.returnTypeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// A `(T, T) -> T` binary operator named like a join/meet.
    static func isSemilatticeOp(_ summary: FunctionSummary) -> Bool {
        curatedVerbs.contains(summary.name) && summary.binaryOperatorTypeSymmetrySignal != nil
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let shape = summary.binaryOperatorTypeSymmetrySignal,
              curatedVerbs.contains(summary.name) else {
            return []
        }
        return [
            shape,
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated semilattice verb match: '\(summary.name)' — combining a value with "
                    + "itself is a no-op, so it owes `op(x, x) == x`"
            )
        ]
    }

    /// Reuses `IdempotenceTemplate.canonicalSignature`'s stable form, namespaced
    /// by the leading template ID so the same function's binary-idempotence,
    /// commutativity, and associativity picks hash distinctly.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "binary-idempotence|" + IdempotenceTemplate.canonicalSignature(of: summary)
        )
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `op(x, x) == x` — combining a value with itself returns that value. It is the "
                + "idempotent leg of a SEMILATTICE; with commutativity and associativity (surfaced "
                + "separately) it characterizes min / max / ∪ / ∩ / gcd / lcm. It is NOT true of "
                + "additive operators: `x + x == x` only at zero.",
            "CONFIRM the operation is a genuine join or meet. `min` / `max` / `union` / `intersection` "
                + "/ `gcd` / `lcm` are idempotent; a `merge` or `combine` that ADDS is not "
                + "(`merge(x, x)` doubles), which is why those verbs are excluded from this template.",
            "T must conform to Equatable for the emitted property to compile."
        ]
    }
}
