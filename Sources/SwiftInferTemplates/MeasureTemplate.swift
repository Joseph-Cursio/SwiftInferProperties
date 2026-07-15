import SwiftInferCore

/// The **measure** role — a `count` / `size` / `magnitude`, and the one free law
/// it owes: **non-negativity**, `measure >= 0`.
///
/// This is the honest boundary the dogfood flagged (`docs/dogfood-new-templates-findings.md`):
/// a lone measure — especially a computed property like `var count: Int`, which
/// `Epic #1` now surfaces — owes almost nothing *universal*. What it *does* owe,
/// by virtue of being a cardinality or a magnitude, is that it is never negative.
/// That is a small law, and saying so is the point — the alternative is a
/// confident suggestion with nothing behind it (the `predicate` template makes
/// the same admission for `Bool`-returning functions).
///
/// **It is nonetheless refutable**, which is why it earns a template while a bare
/// predicate's interesting law does not: integer underflow is a real bug class.
/// `remaining = capacity - used`, `count = end - start`, an `abs` with a sign
/// slip — each can go negative, and a per-element example test that never hits
/// the boundary won't notice. The law rejects exactly those.
///
/// **Signed codomains only.** On a `UInt`-family return the type *already*
/// guarantees `>= 0`, so the law is a compile-time tautology and no suggestion is
/// made; it fires only where a negative is representable (`Int` / `Int8…64`) and
/// therefore possible.
public enum MeasureTemplate {

    /// Curated NON-NEGATIVE measure verbs — cardinalities and magnitudes, which
    /// are non-negative by definition. Deliberately excludes signed measures
    /// (`score`, `balance`, `delta`, `offset`, `weight` — a graph edge weight can
    /// be negative), for which non-negativity would be a false law.
    public static let curatedVerbs: Set<String> = [
        "count", "size", "length", "cardinality", "magnitude",
        "depth", "height", "width"
    ]

    /// Curated suffixes, so `byteCount` / `treeDepth` / `viewWidth` fire.
    public static let curatedSuffixes: [String] = [
        "Count", "Size", "Length", "Width", "Height", "Depth"
    ]

    /// Signed integer codomains — where a negative is representable, so the law
    /// can be violated. `UInt`-family returns are excluded (the type guarantees it).
    public static let signedIntegerCodomains: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "measure-non-negativity",
            appliesTo: Self.isMeasure,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "measure-non-negativity|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            // The value the law quantifies over: the argument for a 1-parameter
            // measure, else the receiver (a 0-parameter measure of `self`).
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// A signed-integer-valued measure named like a cardinality/magnitude, in one
    /// of two shapes: a 0-parameter measure of `self` (a computed property or a
    /// nullary method on a type) or a 1-parameter measure of its argument.
    static func isMeasure(_ summary: FunctionSummary) -> Bool {
        guard hasMeasureName(summary.name),
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              let returnType = summary.returnTypeText,
              signedIntegerCodomains.contains(returnType) else {
            return false
        }
        // 0-param measure of self (property / nullary method): needs a carrier.
        if summary.parameters.isEmpty {
            return summary.containingTypeName != nil
        }
        // 1-param measure of the argument.
        if summary.parameters.count == 1, let param = summary.parameters.first, !param.isInout {
            return true
        }
        return false
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard isMeasure(summary), let returnType = summary.returnTypeText else {
            return []
        }
        let subject = summary.parameters.isEmpty ? "self" : summary.parameters[0].typeText
        // Deliberately Possible-tier (20 + 15 = 35). Non-negativity is the
        // weakest, most-often-trivially-true law in the catalogue — it earns its
        // keep only on the integer-underflow edge — so it sits below the additive
        // `homomorphism` on the same measure and is surfaced only with
        // `--include-possible`, alongside `monotonicity`.
        return [
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "Measure shape: \(subject) -> \(returnType) (a signed-integer measure)"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Curated non-negative-measure verb match: '\(summary.name)' — a cardinality "
                    + "or magnitude, so it owes `measure >= 0`"
            )
        ]
    }

    private static func hasMeasureName(_ name: String) -> Bool {
        if curatedVerbs.contains(name) {
            return true
        }
        return curatedSuffixes.contains { suffix in
            name.count > suffix.count && name.hasSuffix(suffix)
        }
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `measure >= 0` — a cardinality or magnitude is never negative. It is a small "
                + "law, and the honest one for a lone measure: a `count` owes non-negativity by virtue "
                + "of being a count, but the *interesting* invariant (what the count relates to) is "
                + "domain knowledge no signature can recover.",
            "IT IS REFUTABLE where it matters — integer underflow. `capacity - used`, `end - start`, "
                + "an `abs` with a sign slip can all go negative; generate the boundary "
                + "(empty / zero / reversed) on purpose, because that is the only place this fails.",
            "CONFIRM the measure is genuinely non-negative. `count` / `size` / `magnitude` are; a "
                + "signed quantity that happens to be named like one (a `balance`, a `delta`) is not — "
                + "those verbs are deliberately excluded, but a project may reuse a curated name."
        ]
    }
}
