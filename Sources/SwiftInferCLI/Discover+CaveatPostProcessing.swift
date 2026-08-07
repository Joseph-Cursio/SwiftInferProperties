import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Caveat post-processing — the pass that runs over `discover`'s suggestions once the
/// corpus is known, adding or removing "why this might be wrong" lines that a static
/// `Constraint` has no way to decide for itself.
///
/// Split out of `Discover+Pipeline.swift`, which reached SwiftLint's 400-line file cap
/// when the access-restriction rescue landed. The seam is real rather than arithmetic:
/// both helpers here answer "what does the CORPUS say about a caveat the template
/// emitted blind?" — one drops a conformance warning the type declarations disprove,
/// the other adds a remedy the access scan discovered.
extension SwiftInferCommand.Discover {

    /// The `SymbolJoinKey`s a manifest authorises the scan to rescue from the
    /// access-restricted set into template analysis.
    ///
    /// Only **analysable** seeds qualify. A `refactor-pending` kernel has no symbol to
    /// analyse, so offering it to the templates would narrow onto something uncallable and
    /// report a confident zero — the exact failure `SeedKind` was split to prevent. `nil`
    /// manifest yields an empty set, which is what keeps an unseeded run's `private`
    /// functions hidden.
    static func rescuableRestrictedKeys(from seedManifest: SeedManifest?) -> Set<String> {
        Set(
            (seedManifest?.analysableSeeds ?? []).map {
                SymbolJoinKey.make(file: $0.file, symbol: $0.symbol)
            }
        )
    }

    /// Lead a rescued suggestion's caveats with the refactor that unlocks running it.
    ///
    /// A seed can pull an access-restricted function into template analysis, which is the right
    /// answer to "should this law be proposed?" — but the law still cannot be *executed* from a
    /// test until the access widens, not even with `@testable import`. Saying so here rather than
    /// at verify time is the whole point of the split in `SeedKind.restrictedFunction`: access
    /// level belongs in the advice.
    ///
    /// **Prepended, not appended.** The reader decides whether to act on a suggestion from the
    /// first caveat line; a remedy discovered after four paragraphs about generator tuning is a
    /// remedy discovered too late. This mirrors `determinismSuggestion`, which already leads with
    /// `restriction.remedy` for the generic law.
    ///
    /// Keyed on `SymbolJoinKey` so it agrees with the rescue decision itself — a suggestion that
    /// was rescued but not caveated would be strictly worse than not rescuing it, promising a test
    /// the reader cannot write.
    static func withAccessRestrictionCaveats(
        _ suggestions: [Suggestion],
        restrictedFunctions: [RestrictedFunction]
    ) -> [Suggestion] {
        guard !restrictedFunctions.isEmpty else { return suggestions }
        let pairs = restrictedFunctions.map {
            (SymbolJoinKey.make(for: $0.summary), $0.restriction)
        }
        // First wins: the lossy join key can collide (see `SymbolJoinKey`), and two remedies for
        // one key differ only in wording — picking either beats trapping on a duplicate.
        let restrictionByKey = Dictionary(pairs) { first, _ in first }
        return suggestions.map { suggestion in
            let restrictions = suggestion.evidence.compactMap { row in
                restrictionByKey[
                    SymbolJoinKey.make(
                        file: row.location.file,
                        symbol: Self.functionBaseName(row.displayName)
                    )
                ]
            }
            guard let restriction = restrictions.first else { return suggestion }
            var updated = suggestion
            updated.explainability = ExplainabilityBlock(
                whySuggested: suggestion.explainability.whySuggested,
                whyMightBeWrong: [
                    "NO TEST CAN RUN THIS LAW AS WRITTEN: \(restriction.remedy) The law itself is "
                        + "right and the property is worth stating — but the refactor comes "
                        + "first\(Self.effortClause(for: restriction))."
                ] + suggestion.explainability.whyMightBeWrong
            )
            return updated
        }
    }

    /// *"and it is one keyword"* — true of exactly one restriction, and asserted for all four until
    /// 2026-08-06.
    ///
    /// The sentence is the reason a reader acts now rather than later, so it has to be true. For an
    /// enclosing-type blocker it is not merely imprecise but the specific wrong idea: it tells them
    /// the fix is deleting a modifier, which compiles, changes nothing, and leaves the law still
    /// unrunnable. Promising cheapness for a refactor that is not cheap spends the credibility the
    /// caveat exists to build.
    ///
    /// Empty rather than a vaguer clause for the other cases: a caveat that says nothing about
    /// effort is honest, while one that gestures at it without knowing is the same failure smaller.
    static func effortClause(for restriction: AccessRestriction) -> String {
        restriction == .notVisibleToTests ? ", and it is one keyword" : ""
    }

    // Internal rather than `private`: it moved out of `Discover+Pipeline.swift` and its one
    // caller stayed behind, so `private` (file scope) no longer reaches it.
    /// Drop the "T must conform to Equatable" caveat wherever the corpus PROVES the carrier
    /// conforms. Fifteen templates emit it, and it is right for a type the scan never saw declare a
    /// conformance — but noise when the suggestion has already resolved the carrier to `String` in
    /// its own signal line, or to a project type whose declaration says `: Hashable`.
    ///
    /// Applied here rather than inside the templates because `EquatableResolver` needs the corpus,
    /// which a static `Constraint` does not have — and here rather than in
    /// `LiftedSuggestionPipeline`, which is the LIFTED path only and early-returns on a corpus with
    /// no test-lifted artifacts. That mistake cost a debugging round: the filter was wired
    /// somewhere every ordinary suggestion bypasses.
    static func withResolvedConformanceCaveats(
        _ suggestions: [Suggestion],
        typeDecls: [TypeDecl]
    ) -> [Suggestion] {
        ConformanceCaveatFilter.apply(
            to: suggestions,
            resolver: EquatableResolver(typeDecls: typeDecls),
            carrierTypeByIdentity: [:]
        )
    }}
