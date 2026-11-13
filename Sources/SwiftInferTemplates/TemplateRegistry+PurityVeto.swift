import SwiftInferCore

/// The impure-subject veto: withhold a law whose subject this analyzer judges impure
/// **with a witness**.
///
/// ## Why a veto and not a caveat
///
/// A suggestion is a law to be executed as a property test — in-process, over random
/// inputs. SEI's own doc calls `.pure` the most dangerous place to land wrongly for
/// exactly that reason. `predicate :: directoryExists(_:)` is a law whose truth depends
/// on what is on disk: it can pass, fail, or flake with the machine, and until now
/// nothing in the output said so.
///
/// `Signal.vetoWeight` collapses the suggestion to `.suppressed`, which
/// `Discover+Pipeline` filters out of the live set — **and the veto still renders its
/// reason**, because `Signal.formattedLine` writes `"<detail> (veto)"` into
/// `whyMightBeWrong`. A withheld law that cannot say why it was withheld is the failure
/// mode this repo files under *a vocabulary nobody reads*.
///
/// ## The scope was measured before it shipped
///
/// `docs/measurements/purity-veto-precision.md`, scored against the laws that HELD:
///
/// | scope | removed | found a counterexample | passed |
/// |---|---|---|---|
/// | `.refuted` outright | 20 | **0** | **10** |
/// | witness-bearing | 8 | **0** | **2** |
///
/// **Witness-bearing is the shipped scope.** The 8 rows the broad scope would additionally
/// remove are `encode(to:)` under `codable-round-trip` — the one template measured at 100%
/// yield — refuted only by `propagatedTry`, which is the analyzer failing to see past a
/// `try` rather than evidence of an impurity.
///
/// The two passing laws this *does* remove are `isDirectory(_:)` and `isStale(…)`, both
/// filesystem reads. Those are the cases the veto exists for, not its cost.
///
/// ## Every path to a stub, not only this one (2026-11-12)
///
/// The measurement above priced this function, which runs inside `TemplateRegistry.discover`.
/// Two paths reached the stub writers without it: TestLifter's promoted rows, which join later
/// (`applyImpureSubjectVetoByCallee`), and the `--seeds` fallbacks, which synthesize a law for a
/// subject this veto had made uncovered (`SwiftInferCommand.Discover.ImpureSeedGate`). Both apply
/// `isImpureWithWitness`. What they moved on the pinned corpus, and the hand check of every row,
/// is in `docs/measurements/purity-veto-precision.md` under *Two paths around the veto*.
public extension TemplateRegistry {

    /// Veto every suggestion resting on a witness-refuted subject.
    ///
    /// **The scope predicate is `PackagePurityJoin.refutingNames`, reused rather than
    /// restated.** A `.refuted` declaration that does not throw cannot be an
    /// ignorance-only refutation — `propagatedTry` requires a `throws` clause by
    /// definition and `noBody` is structurally unreachable — and a subject the join
    /// retracted carries a witness one hop away.
    static func applyImpureSubjectVeto(
        to suggestions: [Suggestion],
        summaries: [FunctionSummary]
    ) -> [Suggestion] {
        let refutingNames = PackagePurityJoin.refutingNames(in: summaries)
        let summaryAt = Dictionary(summaries.map { ($0.location, $0) }) { first, _ in first }

        return suggestions.map { suggestion in
            let impure = suggestion.evidence.compactMap { row -> FunctionSummary? in
                guard let summary = summaryAt[row.location],
                      isImpureWithWitness(summary, refutingNames: refutingNames)
                else { return nil }
                return summary
            }
            guard !impure.isEmpty else { return suggestion }
            return vetoed(suggestion, on: impure)
        }
    }

    /// The veto's scope as one predicate, for every path that can hand a law to the stub
    /// writers: this veto, `applyImpureSubjectVetoByCallee` for lifted suggestions, and the two
    /// `--seeds` fallbacks (`synthesizeGenericLaws`, `synthesizeMutatorLaws`), which synthesize
    /// their laws after the cut and so never pass through `TemplateRegistry.discover`.
    static func isImpureWithWitness(_ summary: FunctionSummary, refutingNames: Set<String>) -> Bool {
        // **`.refuted` is `FunctionSummary.init`'s DEFAULT**, so on a summary nothing
        // analysed it means *not computed*, not *refuted*. The body fingerprint is the
        // discriminator, and the field's own doc states the semantics: `nil` for "summaries
        // built without a body — a protocol requirement, or one of the many hand-built
        // summaries in tests."
        //
        // Without this the veto fires on every hand-built summary, which is item 40's
        // finding — a verdict that is an initialiser default — biting a consumer instead of
        // an advisory. Six suites went `.suppressed` before this gate existed, and
        // `defaultedVerdictIsNotEvidence` is what keeps them that way.
        summary.bodyFingerprint != nil
            && summary.purityVerdict == .refuted
            && (!summary.isThrows || summary.calledFreeFunctionNames.contains(where: refutingNames.contains))
    }

    /// The same veto for suggestions TestLifter promoted, which join after
    /// `TemplateRegistry.discover` and so never met `applyImpureSubjectVeto`.
    ///
    /// **A lifted row cannot be matched by location.** Its evidence sits at the test assertion
    /// it was lifted from (`LiftedSuggestion.site`), or at `<corpus>` for a corpus-wide
    /// finding, never at the production declaration. The callee is all it names, and
    /// TestLifter's own recovery matches it by bare name (`LiftedSuggestionRecovery`). So the
    /// match here is by name too, and **unanimous**: a row is vetoed only when every
    /// production function of that name is impure with a witness. A pure namesake, an
    /// overload or a method of the same name on another type, leaves the row alone, because
    /// the test body may have meant it, and a namesake must not lend its verdict either way.
    static func applyImpureSubjectVetoByCallee(
        to suggestions: [Suggestion],
        summaries: [FunctionSummary]
    ) -> [Suggestion] {
        let refutingNames = PackagePurityJoin.refutingNames(in: summaries)
        let namesakes = Dictionary(grouping: summaries, by: \.name)
        return suggestions.map { suggestion in
            let impure = suggestion.evidence.flatMap { row -> [FunctionSummary] in
                guard let candidates = namesakes[calleeName(of: row.displayName)],
                      candidates.allSatisfy({ isImpureWithWitness($0, refutingNames: refutingNames) })
                else { return [] }
                return candidates
            }
            guard !impure.isEmpty else { return suggestion }
            return vetoed(suggestion, on: impure)
        }
    }

    /// `normalize(_:)` → `normalize`; `Codec.encode(_:)` → `encode`. An operator is its whole
    /// spelling: `..<(_:_:)` is `..<`, never `<`.
    private static func calleeName(of displayName: String) -> String {
        let base = displayName.prefix { $0 != "(" }
        guard let first = base.first, first.isLetter || first == "_" else { return String(base) }
        return String(base.split(separator: ".").last ?? base[...])
    }

    private static func vetoed(_ suggestion: Suggestion, on impure: [FunctionSummary]) -> Suggestion {
        let named = Set(impure.map(\.name)).sorted().joined(separator: ", ")
        let signal = Signal(
            kind: .impureSubject,
            weight: Signal.vetoWeight,
            detail: "subject is judged impure with a witness (\(named)) — a generated law would "
                + "execute that impurity in-process"
        )
        var updated = suggestion
        updated.score = Score(signals: suggestion.score.signals + [signal])
        updated.explainability = ExplainabilityBlock(
            whySuggested: suggestion.explainability.whySuggested,
            whyMightBeWrong: suggestion.explainability.whyMightBeWrong + [signal.formattedLine]
        )
        return updated
    }
}
