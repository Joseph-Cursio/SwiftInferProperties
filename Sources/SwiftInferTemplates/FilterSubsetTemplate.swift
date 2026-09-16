import SwiftInferCore

/// The **filter** role — a `[T], … -> [T]` that *selects* a sub-collection, and
/// the one refutable law it owes: **subset**, `Set(result) ⊆ Set(haystack)`.
///
/// This is the application-shape gap the SwiftLintRuleStudio road-test surfaced
/// (`docs/measurements/roadtest-swiftlintrulestudio.md`): a filter like
/// `filterViolations([Violation], …) -> [Violation]` matched no template, so the
/// pipeline fell back to the `f(x) == f(x)` determinism tautology. A filter owes
/// something better and refutable — it returns only elements it was given.
///
/// **The name gates the shape, deliberately.** `[T] -> [T]` alone owes nothing:
/// a `map` (`[1,2] -> [2,4]`) has that shape and violates subset without any bug.
/// Subset is owed only once a `filter` / `select` / `keep` name asserts the
/// function *selects* rather than *transforms*. Once it does, the **name is the
/// contract** — a `filter` returning a non-member is a bug or a lie about the name
/// — which is why `filter-subset` is a member of
/// `Refutability.roleEntailedTemplates` rather than a conjecture like
/// `idempotence` / `monotonicity`, where `get(key) -> key.count` is correct yet
/// non-monotone. It stays Possible-tier on score and reaches a default run
/// through the role-entailed path, not through `--include-possible`.
///
/// **The verb must be the name's ONLY operation, and that gate is measured, not
/// assumed (#476).** Admission to `roleEntailedTemplates` rests on the name
/// bounding the promise, and a verb *prefix* does not bound a compound name —
/// the tail can revoke it. `pbt-book`'s `filterThenMap(_ values: [Int]) -> [Int]`
/// is `values.filter { $0 > 10 }.map { $0 * 2 }`: honestly named, entirely
/// correct, and `Set([22]) ⊆ Set([11])` is **false**. The shipped binary proposed
/// subset on it — at Possible 35, on a run with no `--include-possible`, under a
/// stub header reading *ENTAILED — a correct implementation cannot fail this*.
/// `nameAnnouncesASecondOperation` is the fix: a connective (`…Then…`, `…And…`)
/// or a transform verb in the tail means the name promises two operations, so
/// subset is not owed and nothing is proposed.
///
/// Contrast the sibling admitted under the identical standard,
/// `caseiterable-key-injectivity`: it matches `hasSuffix` on nouns (`…Key`), where
/// the matched token *is* the head of the name and no tail can follow it. Verbs
/// lead and nouns trail, so a verb-gated template needs this check and a
/// noun-gated one does not.
///
/// **It is refutable**, which earns it a template: a "filter" that quietly maps,
/// appends a default, or reads from another source returns an element that was
/// never in the input — and this law rejects exactly that.
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
        // Possible-tier on SCORE (20 + 15 = 35) but role-entailed, so it reaches a
        // default run through `Refutability.isWorthSurfacingBelowCut` rather than
        // through `--include-possible`. That is the opposite posture from
        // `idempotence` / `monotonicity`: the name here IS the contract, which is
        // what `nameAnnouncesASecondOperation` exists to keep true.
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
        guard curatedVerbPrefixes.contains(where: { lowered.hasPrefix($0) }) else { return false }
        return !nameAnnouncesASecondOperation(name)
    }

    /// Connectives that announce a SECOND operation, whatever it turns out to be.
    ///
    /// This is the general half of the gate and the cheaper one to be sure of: `filterThenMap`,
    /// `collectAndTransform`, `selectAndSort` all promise two things, and only the first is
    /// selection. What the second one *is* does not matter — `sort` preserves subset and `map`
    /// does not — because the name no longer bounds the promise, and role-entailment is a claim
    /// about what the name bounds.
    ///
    /// Matched as whole camelCase tokens, never as substrings, so `filterAndroidTargets`
    /// tokenises to `android` and survives. `StreamConsumption.camelCaseTokens` is the
    /// tokeniser the monotonicity subject census settled on for exactly this reason: an exact
    /// whole-name match missed `_cos`, and a substring match read `distance(to:)` as trig.
    static let secondOperationConnectives: Set<String> = ["and", "then", "plus"]

    /// Verbs that name an operation applied to the ELEMENTS, so a name carrying one promises a
    /// transform however it is spelled — `filterMappedRules`, `selectNormalizedPaths`.
    ///
    /// **Kept deliberately short.** The cost of a wrong entry here is a real law withdrawn, so
    /// only tokens with no plausible noun or adjective reading are admitted. `build`, `make`,
    /// `render`, `format`, `compute`, `generate` and `resolve` are all EXCLUDED for failing that
    /// test — `filterBuildSettings` and `filterRenderedLines` are ordinary filters whose tail is
    /// a noun phrase, and withdrawing them to catch a hypothetical would be the Daikon trap in
    /// the gate rather than in the filter list.
    static let transformVerbs: Set<String> = [
        "map", "mapped", "mapping",
        "transform", "transformed",
        "convert", "converted",
        "derive", "derived",
        "normalize", "normalized", "normalise", "normalised",
        "rewrite", "rewritten",
        "expand", "expanded"
    ]

    /// Whether the name promises an operation BEYOND selection, so subset is not owed (#476).
    ///
    /// The leading token is the selection verb that admitted the name; only the tail is read.
    /// Measured cost, same binary either side: the seventeen sibling repositories go 12 rows to
    /// 11 — exactly one, and the one is the false law — and the twenty manifest corpora do not
    /// move at all. See `docs/measurements/subset-name-contract-gate.md`.
    static func nameAnnouncesASecondOperation(_ name: String) -> Bool {
        let tail = StreamConsumption.camelCaseTokens(name).dropFirst()
        return tail.contains { token in
            secondOperationConnectives.contains(token) || transformVerbs.contains(token)
        }
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `Set(result) ⊆ Set(haystack)` — a filter returns only elements it was given. "
                + "It is refutable where it matters: a `filter` that quietly maps, appends a default, or "
                + "reads from another source returns an element that was never in the input, and this "
                + "law rejects exactly that.",
            "THE NAME IS WHAT OWES THIS, not the shape. A `[T] -> [T]` that TRANSFORMS its elements "
                + "(a map: `[1,2] -> [2,4]`) has the same shape and no such obligation — subset is owed "
                + "here because the name asserts SELECTION, and a name that also announces a transform "
                + "(`filterThenMap`) is rejected rather than proposed. If this function nevertheless "
                + "transforms what it returns, that is a finding about the NAME.",
            "The element type must be Equatable (or Hashable) for the membership check to compile. "
                + "This tool does not verify conformance — confirm before applying.",
            "Bias the generator so elements COLLIDE (a small alphabet, repeated values): a filter that "
                + "mishandles equal-but-distinct elements fails only where the input repeats."
        ]
    }
}
