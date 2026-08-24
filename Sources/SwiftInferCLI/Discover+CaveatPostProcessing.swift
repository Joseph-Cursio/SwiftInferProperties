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
        restrictedFunctions: [RestrictedFunction],
        summaries: [FunctionSummary] = []
    ) -> [Suggestion] {
        guard !restrictedFunctions.isEmpty else { return suggestions }
        // **Join on the exact coordinate, not on `(file, bare symbol)`.** Both sides of THIS join
        // come from one scan, so the declaration's own `file:line` identifies it exactly, and the
        // lossy key does not: it collapses every same-named function in a file to one entry, and
        // `Dictionary(_:uniquingKeysWith:)` then binds that entry to whichever came first.
        //
        // Measured on `MacPaw/OpenAI` @ `a532be8`, 2026-08-24: `Components.swift` declares **72**
        // `func encode(`, of which exactly ONE — inside a `private struct Storage` — is genuinely
        // restricted. Under the lossy key all 72 shared `Components.swift::encode`, so that one
        // `private` nested type carried `.enclosingTypeNotVisibleToTests` onto **26 of the 28**
        // `codable-round-trip` suggestions in the file. `blocksEveryTest` then marked each
        // `subjectNotVisibleToTests` and `verify` filed them `not-a-candidate` — a law suppressed
        // by a claim about a DIFFERENT function that happened to share a name.
        //
        // The old comment read *"two remedies for one key differ only in wording — picking either
        // beats trapping on a duplicate"*. That premise is what failed: the colliding remedies did
        // not differ in wording, they differed in **truth**. `SymbolJoinKey`'s own doc calls the
        // collision *"a known, currently-empty hazard"* — measured on seeds, across FILES. This
        // collision is WITHIN one file, which that measurement could not have seen.
        let byLocation = Dictionary(
            restrictedFunctions.map { (Self.coordinate(of: $0.summary.location), $0.restriction) }
        ) { first, _ in first }
        // The lossy key survives for rows with no resolvable coordinate — a lifted row locates at
        // `<test-body>:0`, so an exact join would silently drop its caveat. Narrow fallback, not a
        // general one: a row that HAS a coordinate and misses is not restricted, and must not
        // inherit a namesake's verdict.
        let pairs = restrictedFunctions.map {
            (SymbolJoinKey.make(for: $0.summary), $0.restriction)
        }
        let restrictionByKey = Dictionary(pairs) { first, _ in first }
        // §2's remedy, now that it is computable. `calledFreeFunctionNames` landed for the
        // one-hop purity join on 2026-08-18 and inverting it names the caller — the blocker
        // this advice waited eleven days on was open item 38's missing call graph.
        let lifts = LiftTargets.make(summaries: summaries, restrictedFunctions: restrictedFunctions)
        return suggestions.map { suggestion in
            let restriction = Self.restriction(
                for: suggestion,
                byLocation: byLocation,
                byName: restrictionByKey
            )
            guard let restriction else { return suggestion }
            var updated = suggestion
            // The caveat below has always SAID this law cannot run. Say it as a signal too, so
            // `StructuralBlocker` can key on it and `verify` stops filing a known-unrunnable
            // entry as `build-failed`. Weight 0 — the row's score and tier are unchanged, because
            // §2's remedy is to LIFT the law, and demoting it would suppress that advice.
            if Self.blocksEveryTest(restriction) {
                updated.score = Score(advisorySignals: suggestion.score.signals + [
                    Signal(
                        kind: .subjectNotVisibleToTests,
                        weight: 0,
                        detail: "no test can name the subject: \(restriction.remedy)"
                    )
                ])
            }
            // The lift line follows the remedy and precedes everything else: it is the
            // ACTIONABLE half, and §2 argues it is the better of the two remedies the
            // `restriction.remedy` sentence offers. Absent when no visible caller was found,
            // rather than hedged — a caveat naming nothing is worse than one line fewer.
            let liftLine = Self.liftCaveat(for: suggestion, lifts: lifts)
            updated.explainability = ExplainabilityBlock(
                whySuggested: suggestion.explainability.whySuggested,
                whyMightBeWrong: [
                    "NO TEST CAN RUN THIS LAW AS WRITTEN: \(restriction.remedy) The law itself is "
                        + "right and the property is worth stating — but the refactor comes "
                        + "first\(Self.effortClause(for: restriction))."
                ] + liftLine + suggestion.explainability.whyMightBeWrong
            )
            return updated
        }
    }

    /// The restriction binding a suggestion, found per-declaration.
    ///
    /// **Exact coordinate first, and a miss is an answer.** A row that carries a resolvable
    /// `file:line` and finds nothing is *not restricted* — it must not fall through to the name
    /// key and inherit a namesake's verdict, which is the whole defect this join was narrowed to
    /// fix. The name key is reached only when there is no coordinate to ask with.
    static func restriction(
        for suggestion: Suggestion,
        byLocation: [String: AccessRestriction],
        byName: [String: AccessRestriction]
    ) -> AccessRestriction? {
        for row in suggestion.evidence {
            guard row.location.isResolvable else {
                let key = SymbolJoinKey.make(
                    file: row.location.file,
                    symbol: Self.functionBaseName(row.displayName)
                )
                if let found = byName[key] { return found }
                continue
            }
            if let found = byLocation[Self.coordinate(of: row.location)] { return found }
        }
        return nil
    }

    /// `file:line` — the declaration's identity for the restriction join.
    ///
    /// **Line without column deliberately.** Both sides come from one scan, so the line agrees;
    /// the column is where a producer is most likely to differ (a modifier list, an attribute, or
    /// a leading-trivia choice moves it), and a coordinate that is exact in principle but brittle
    /// in practice would reintroduce the miss this join exists to remove — silently, and in the
    /// permissive direction the standing observation warns about.
    static func coordinate(of location: SourceLocation) -> String {
        "\(location.file)#\(location.line)"
    }

    /// The lift line for a suggestion, or `[]` when no evidence row has a visible caller.
    ///
    /// Returns an array so the caller can concatenate without an optional dance, and
    /// returns **empty rather than a hedge** when nothing was found: a caveat naming no
    /// caller is worse than one line fewer.
    static func liftCaveat(for suggestion: Suggestion, lifts: LiftTargets) -> [String] {
        for row in suggestion.evidence {
            if let line = lifts.caveat(for: row.location) { return [line] }
        }
        return []
    }

    /// Whether the restriction puts the subject beyond EVERY test, not merely beyond an
    /// ordinary import.
    ///
    /// `.internalOrSPI` is deliberately excluded: `@testable` promotes `internal`, so those rows
    /// verify today and blocking them would suppress working laws. `.nestedLocal` is also
    /// unreachable in principle but is left out until measured, on the same conservative footing —
    /// the cost of a wrong inclusion is a row that silently stops being verified.
    static func blocksEveryTest(_ restriction: AccessRestriction) -> Bool {
        switch restriction {
        case .notVisibleToTests, .enclosingTypeNotVisibleToTests: true
        case .internalOrSPI, .nestedLocal: false
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
