import SwiftInferCore

/// The **filter** role — a `[T], … -> [T]` that *selects* a sub-collection, and
/// the one refutable law it owes: **subset**, `Set(result) ⊆ Set(haystack)`.
///
/// This is the application-shape gap the SwiftLintRuleStudio road-test surfaced
/// (`docs/roadtest-swiftlintrulestudio.md`): a filter like
/// `filterViolations([Violation], …) -> [Violation]` matched no template, so the
/// pipeline fell back to the `f(x) == f(x)` determinism tautology. A filter owes
/// something better and refutable — it returns only elements it was given.
///
/// **The name gates the shape, deliberately.** `[T] -> [T]` alone owes nothing:
/// a `map` (`[1,2] -> [2,4]`) has that shape and violates subset without any bug.
/// Subset is entailed only once a `filter` / `select` / `keep` name asserts the
/// function *selects* rather than *transforms* — so it is a **name-conjecture**
/// (like `idempotence` / `monotonicity`), refutable but Possible-tier, and left
/// for the seed focus to narrow. It is not marked role-entailed for exactly this
/// reason: a correct `map` would fail it.
///
/// **It is nonetheless refutable**, which earns it a template: a "filter" that
/// quietly maps, appends a default, or reads from another source returns an
/// element that was never in the input — and this law rejects exactly that.
public enum FilterSubsetTemplate {

    /// Curated filter/selection verb *prefixes* (matched lower-cased against the
    /// function name). A name beginning with one asserts the function selects a
    /// sub-collection, so `result ⊆ input` is owed.
    public static let curatedVerbPrefixes: [String] = [
        "filter", "select", "keep", "retain", "matching", "applicable",
        "restrict", "prune", "exclude", "reject", "only", "drop"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "filter-subset",
            appliesTo: Self.isFilter,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "filter-subset|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            // The collection the law quantifies over: the parameter that shares the
            // return's array type — the haystack `result` must be a subset of.
            carrierType: { summary in Self.haystackType(of: summary) ?? summary.containingTypeName },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// A non-mutating, non-throwing, synchronous function with a curated filter
    /// name that returns `[T]` and takes some `[T]` parameter (same element type).
    static func isFilter(_ summary: FunctionSummary) -> Bool {
        guard hasFilterName(summary.name),
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              let returnType = summary.returnTypeText,
              let returnElement = arrayElement(of: returnType) else {
            return false
        }
        // Some parameter must be `[returnElement]` — the collection being selected from.
        return summary.parameters.contains { parameter in
            !parameter.isInout && arrayElement(of: parameter.typeText) == returnElement
        }
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard isFilter(summary),
              let returnType = summary.returnTypeText,
              let element = arrayElement(of: returnType) else {
            return []
        }
        // Possible-tier (20 + 15 = 35): a name-conjecture, narrowed by the seed
        // focus, surfaced with `--include-possible` — the same posture as
        // `idempotence` / `monotonicity`, and for the same reason (a `map` fails it).
        return [
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "Filter shape: [\(element)], … -> [\(element)] (selects a sub-collection)"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Curated filter/selection verb match: '\(summary.name)' — it selects, "
                    + "so it owes `result ⊆ input`"
            )
        ]
    }

    /// The type of the parameter the result must be a subset of.
    static func haystackType(of summary: FunctionSummary) -> String? {
        guard let returnType = summary.returnTypeText,
              let returnElement = arrayElement(of: returnType) else {
            return nil
        }
        return summary.parameters.first { parameter in
            !parameter.isInout && arrayElement(of: parameter.typeText) == returnElement
        }?.typeText
    }

    /// The element of an array type: `[Violation]` → `Violation`,
    /// `Array<Rule>` → `Rule`. A dictionary (`[String: Rule]`) is not an array, so
    /// the top-level-colon form returns `nil`.
    static func arrayElement(of type: String) -> String? {
        if type.hasPrefix("["), type.hasSuffix("]") {
            let inner = type.dropFirst().dropLast()
            return inner.contains(":") ? nil : String(inner)
        }
        if type.hasPrefix("Array<"), type.hasSuffix(">") {
            return String(type.dropFirst("Array<".count).dropLast())
        }
        return nil
    }

    private static func hasFilterName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return curatedVerbPrefixes.contains { lowered.hasPrefix($0) }
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `Set(result) ⊆ Set(haystack)` — a filter returns only elements it was given. "
                + "It is refutable where it matters: a `filter` that quietly maps, appends a default, or "
                + "reads from another source returns an element that was never in the input, and this "
                + "law rejects exactly that.",
            "SUBSET IS NAME-CONJECTURED, not shape-entailed. A `[T] -> [T]` that TRANSFORMS its "
                + "elements (a map: `[1,2] -> [2,4]`) has the same shape and is a false positive — the "
                + "law holds only because the NAME asserts selection. Confirm the function selects "
                + "rather than transforms.",
            "The element type must be Equatable (or Hashable) for the membership check to compile. "
                + "SwiftInfer M1 does not verify conformance — confirm before applying.",
            "Bias the generator so elements COLLIDE (a small alphabet, repeated values): a filter that "
                + "mishandles equal-but-distinct elements fails only where the input repeats."
        ]
    }
}
