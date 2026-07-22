import PropertyLawCore
import SwiftInferCore

/// The **selection** role — `filter-subset`'s sibling for when the collection the
/// result is a subset of lives *inside a container argument* rather than being
/// passed directly. `layerChain(URL, ConfigTree) -> [DiscoveredConfig]` returns a
/// subset of `ConfigTree.configs`, so it owes `Set(result) ⊆ Set(container.configs)`
/// — a law `filter-subset` cannot see because no argument is a bare
/// `[DiscoveredConfig]`. (SwiftLintRuleStudio road-test, cause 1: no selection
/// template named `layerChain`'s shape, so it fell to the `f(x)==f(x)` tautology.)
///
/// Shapes-aware: it consults the corpus `TypeShape` index to find the container's
/// `[T]`-typed member, so it can't live in the shapes-free single-function
/// registry — it gets its own collection pass, like `partition`.
///
/// **Name-gated, deliberately.** A `(X, Container) -> [T]` that *derives* new
/// elements from the container (a `map`) has the same shape and would fail subset;
/// only a `select` / `applicable` / `layer` name asserts selection. So it is a
/// Possible-tier name-conjecture, narrowed by the seed focus — not role-entailed.
public enum SelectionSubsetTemplate {

    /// Selection verb prefixes (lower-cased). A name beginning with one asserts
    /// the function *selects* a sub-collection of a container it was handed.
    public static let curatedVerbPrefixes: [String] = [
        "select", "filter", "keep", "retain", "matching", "applicable",
        "gather", "collect", "resolve", "restrict", "only", "pick", "choose",
        "layer", "chain", "ancestor", "lineage", "descendant"
    ]

    /// The resolved container/member/element for a matching selection.
    struct Match: Sendable, Equatable {
        let containerType: String
        let collectionMember: String
        let elementType: String
    }

    public static func suggest(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Suggestion? {
        guard let match = selectionMatch(for: summary, shapesByName: shapesByName) else { return nil }
        return ConstraintRunner.suggest(constraint: makeConstraint(match: match), subject: summary)
    }

    /// The container type to generate for the emitted law, or nil when no match.
    static func containerType(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> String? {
        selectionMatch(for: summary, shapesByName: shapesByName)?.containerType
    }

    /// Matches a non-mutating, non-throwing, synchronous function with a selection
    /// name that returns `[T]` and takes a *container* argument (a corpus type with
    /// a `[T]` stored member) — but NO bare `[T]` argument (that is `filter-subset`).
    static func selectionMatch(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Match? {
        guard hasSelectionName(summary.name),
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              let returnType = summary.returnTypeText,
              let element = FilterSubsetTemplate.arrayElement(of: returnType) else {
            return nil
        }
        // A bare `[element]` argument is `filter-subset`'s job — don't double up.
        let hasDirectHaystack = summary.parameters.contains { parameter in
            FilterSubsetTemplate.arrayElement(of: parameter.typeText) == element
        }
        guard !hasDirectHaystack else { return nil }

        for parameter in summary.parameters {
            guard let shape = shapesByName[bareTypeName(parameter.typeText)] else { continue }
            if let member = shape.storedMembers.first(
                where: { FilterSubsetTemplate.arrayElement(of: $0.typeName) == element }
            ) {
                return Match(
                    containerType: shape.name,
                    collectionMember: member.name,
                    elementType: element
                )
            }
        }
        return nil
    }

    static func makeConstraint(match: Match) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "selection-subset",
            appliesTo: { _ in true },
            signals: { _ in Self.signals(match: match) },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "selection-subset|" + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { _ in match.containerType },
            carrierType: { _ in match.containerType },
            caveats: { _ in Self.makeCaveats(match: match) }
        )
    }

    static func signals(match: Match) -> [Signal] {
        // Possible-tier (20 + 15 = 35), the same name-conjecture posture as
        // `filter-subset` / `idempotence`.
        [
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "Selection shape: (…, \(match.containerType)) -> [\(match.elementType)] "
                    + "— selects from `\(match.containerType).\(match.collectionMember)`"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Curated selection verb match — it selects, so it owes "
                    + "`result ⊆ \(match.containerType).\(match.collectionMember)`"
            )
        ]
    }

    static func bareTypeName(_ type: String) -> String {
        var bare = type
        if bare.hasSuffix("?") { bare = String(bare.dropLast()) }
        return bare
    }

    private static func hasSelectionName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return curatedVerbPrefixes.contains { lowered.hasPrefix($0) }
    }

    static func makeCaveats(match: Match) -> [String] {
        [
            "THE LAW IS `Set(result) ⊆ Set(\(match.containerType).\(match.collectionMember))` — a "
                + "selection returns only elements the container already held. A `select`/`layer`/… "
                + "that maps, appends, or reads elsewhere returns one that was never in the container, "
                + "and this law rejects exactly that.",
            "SUBSET IS NAME-CONJECTURED, not shape-entailed. A `(X, \(match.containerType)) -> "
                + "[\(match.elementType)]` that TRANSFORMS the members has the same shape and is a "
                + "false positive — the law holds only because the NAME asserts selection.",
            "The element type must be Equatable (or Hashable) for the membership check to compile; "
                + "SwiftInfer M1 does not verify conformance — confirm before applying."
        ]
    }
}
