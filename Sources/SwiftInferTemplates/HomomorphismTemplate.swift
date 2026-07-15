import SwiftInferCore

/// The **homomorphism / structure-preservation** law, in its most recognizable
/// and refutable instance: an **additive measure over concatenation**,
/// `h(a + b) == h(a) + h(b)`.
///
/// A measure `h: [T] -> Int` (`count`, `length`, `size`, `sum`, …) is a monoid
/// homomorphism from `([T], +)` to `(Int, +)`: measuring a concatenation equals
/// summing the measures. This is where the bugs a per-element test never finds
/// actually live — a `count` that double-counts a boundary element, a `sum` that
/// drops the last item, a `byteCount` that mishandles a chunk seam. The failure
/// is a property of how the function behaves *across a join*, which an example
/// on a single input cannot express and a generator can.
///
/// **Deliberately narrow, because the law's truth is domain-specific.** The
/// homomorphism holds only when the source operation is *free* concatenation:
///   - **Array `[T]`** — `(a + b).count == a.count + b.count` is exact. ✓ the
///     one domain this template accepts.
///   - **String** — EXCLUDED. `.count` is grapheme count, which is NOT additive
///     across a combining-character boundary (`"e" + "◌́"` is one grapheme, not
///     two), so `count(a + b) == count(a) + count(b)` is false in general.
///   - **Set** — EXCLUDED (not array-shaped). `|A ∪ B| <= |A| + |B|`, with
///     equality only when disjoint — the measure is sub-additive, not additive.
///   - **Double / Float codomain** — EXCLUDED. Floating-point `+` is not
///     associative, so `sum(a + b)` and `sum(a) + sum(b)` can differ by rounding
///     under exact `==`.
///
/// So the template fires only on an **integer-valued measure over an array**,
/// where the law is genuinely entailed — and a curated verb is required, because
/// the `[T] -> Int` shape alone is every accessor, not every homomorphism.
public enum HomomorphismTemplate {

    /// Curated measure verbs — functions whose result is an additive quantity
    /// over the elements: `count`/`length`/`size`/`cardinality` (element count),
    /// `sum`/`total`/`tally` (element aggregate). All are additive over
    /// concatenation; none is idempotent or max-like.
    public static let curatedVerbs: Set<String> = [
        "count", "length", "size", "cardinality",
        "sum", "total", "tally"
    ]

    /// Curated suffixes, so `byteCount` / `wordCount` / `lineTotal` fire without
    /// every project enumerating the prefixed forms.
    public static let curatedSuffixes: [String] = [
        "Count", "Length", "Size", "Total"
    ]

    /// Integer codomains only. A measure returns a whole quantity, and integer
    /// `+` is exact — unlike `Double`/`Float`, where non-associative rounding
    /// breaks the law under `==`.
    public static let integerCodomains: Set<String> = [
        "Int", "UInt",
        "Int8", "Int16", "Int32", "Int64",
        "UInt8", "UInt16", "UInt32", "UInt64"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "homomorphism",
            appliesTo: Self.isAdditiveMeasure,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.containingTypeName },
            // The law quantifies over the array domain `[T]`, so the generator
            // carrier is the parameter type, not the owning type.
            carrierType: { $0.parameters.first?.typeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// An integer-valued measure named like one, over an array `[T]`.
    static func isAdditiveMeasure(_ summary: FunctionSummary) -> Bool {
        guard hasMeasureName(summary.name),
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              isArrayShaped(param.typeText),
              let returnType = summary.returnTypeText,
              integerCodomains.contains(returnType) else {
            return false
        }
        return true
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard isAdditiveMeasure(summary),
              let param = summary.parameters.first,
              let returnType = summary.returnTypeText else {
            return []
        }
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Additive-measure shape: \(param.typeText) -> \(returnType) "
                    + "(integer measure over an array)"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated measure verb match: '\(summary.name)' — an additive quantity over "
                    + "the elements, so it owes `h(a + b) == h(a) + h(b)`"
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

    /// A plain array `[T]` — starts `[`, ends `]`, and carries no `:` (which
    /// would make it a dictionary `[K: V]`, whose `+` is not defined). Slices and
    /// `ContiguousArray` are excluded because their `+` does not return `Self`.
    private static func isArrayShaped(_ typeText: String) -> Bool {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[")
            && trimmed.hasSuffix("]")
            && !trimmed.contains(":")
    }

    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "homomorphism|" + IdempotenceTemplate.canonicalSignature(of: summary)
        )
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `h(a + b) == h(a) + h(b)` — measuring a concatenation equals summing the "
                + "measures. It holds because array `+` is FREE concatenation: it appends without "
                + "dropping or merging. Confirm `h` is a genuine additive measure — a `count` / `sum` "
                + "/ `size`, not a `max` (`max(a + b) != max(a) + max(b)`) or a de-duplicating count.",
            "IT IS NOT true over every container. On a `Set`, `|A ∪ B| <= |A| + |B|` (equality only "
                + "when disjoint); on a `String`, grapheme `.count` is not additive across a "
                + "combining-character boundary. This template accepts only `[T]` for that reason.",
            "T's element type needs no conformance, but the array itself must compose with `+` "
                + "(all `[T]` do). The measure must be TOTAL — a partial measure that traps on some "
                + "input fails on the harness rather than on the code."
        ]
    }
}
