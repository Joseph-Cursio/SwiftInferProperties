import SwiftInferCore

// MARK: - Multiplicative form: h(a * b) == h(a) * h(b)

/// The multiplicative sibling of the additive-measure homomorphism. Where the
/// additive form is a measure over concatenation (`[T] -> Int`, source `+`), this
/// is a measure over MULTIPLICATION (`Int -> Int`, source `*`): `abs` / `magnitude`
/// / `signum` satisfy `|xy| = |x||y|` and `sign(xy) = sign(x) sign(y)`.
///
/// Emits a distinct `templateName` (`multiplicative-homomorphism`) so the verify
/// path and the catalog anchor dispatch cleanly without having to disambiguate the
/// source operation from the signature. Scoped to `Int` on both sides — the law is
/// exact there, and `*` overflow is bounded away in the verifier.
extension HomomorphismTemplate {

    /// Curated multiplicative measures — each satisfies `h(a * b) == h(a) * h(b)`.
    /// `norm` / `determinant` are deliberately excluded: a p-norm is not
    /// multiplicative, and a determinant's domain is a matrix, not `Int`.
    public static let multiplicativeVerbs: Set<String> = [
        "abs", "magnitude", "sign", "signum"
    ]

    /// The `multiplicative-homomorphism` suggestion for `summary`, or `nil` when it does not apply.
    public static func suggestMultiplicative(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeMultiplicativeConstraint(), subject: summary)
    }

    static func makeMultiplicativeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "multiplicative-homomorphism",
            appliesTo: Self.isMultiplicativeHomomorphism,
            signals: Self.multiplicativeSignals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "multiplicative-homomorphism|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText },
            caveats: { _ in Self.makeMultiplicativeCaveats() }
        )
    }

    /// A curated multiplicative measure `Int -> Int`. Scoped to `Int` on both
    /// sides: exact `*`, and the one type the verifier's bounded generator covers.
    static func isMultiplicativeHomomorphism(_ summary: FunctionSummary) -> Bool {
        guard multiplicativeVerbs.contains(summary.name),
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              param.typeText == "Int",
              summary.returnTypeText == "Int" else {
            return false
        }
        return true
    }

    static func multiplicativeSignals(for summary: FunctionSummary) -> [Signal] {
        guard isMultiplicativeHomomorphism(summary) else {
            return []
        }
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Multiplicative-measure shape: Int -> Int"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated multiplicative-measure verb match: '\(summary.name)' — "
                    + "`|xy| = |x||y|`, so it owes `h(a * b) == h(a) * h(b)`"
            ),
        ]
    }

    static func makeMultiplicativeCaveats() -> [String] {
        [
            "THE LAW IS `h(a * b) == h(a) * h(b)` — a homomorphism from `(Int, ×)` to `(Int, ×)`. "
                + "It holds for `abs` / `magnitude` / `signum` (`|xy| = |x||y|`, `sign(xy) = "
                + "sign(x)·sign(y)`). It is NOT true of additive measures (`count(a * b)` is "
                + "meaningless) or of `max` / `min`.",
            "MIND OVERFLOW. `a * b` and `h(a) * h(b)` trap on overflow for large operands, and "
                + "`abs(Int.min)` has no positive representation — so the property must be checked "
                + "over a BOUNDED domain (the verifier draws from ±10_000). A counterexample, if one "
                + "exists, lives in the sign/measure logic, not at the numeric extremes.",
            "T must conform to Equatable for the emitted property to compile (Int does).",
        ]
    }
}
