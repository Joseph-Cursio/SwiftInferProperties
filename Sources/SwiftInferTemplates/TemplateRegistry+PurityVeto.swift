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
                      // **`.refuted` is `FunctionSummary.init`'s DEFAULT**, so on a summary
                      // nothing analysed it means *not computed*, not *refuted*. The body
                      // fingerprint is the discriminator, and the field's own doc states the
                      // semantics: `nil` for "summaries built without a body — a protocol
                      // requirement, or one of the many hand-built summaries in tests."
                      //
                      // Without this the veto fires on every hand-built summary, which is
                      // item 40's finding — a verdict that is an initialiser default — biting
                      // a consumer instead of an advisory. Six suites went `.suppressed`
                      // before this gate existed, and `defaultedVerdictIsNotEvidence` is what
                      // keeps them that way.
                      summary.bodyFingerprint != nil,
                      summary.purityVerdict == .refuted,
                      !summary.isThrows
                        || summary.calledFreeFunctionNames.contains(where: refutingNames.contains)
                else { return nil }
                return summary
            }
            guard !impure.isEmpty else { return suggestion }
            return vetoed(suggestion, on: impure)
        }
    }

    private static func vetoed(_ suggestion: Suggestion, on impure: [FunctionSummary]) -> Suggestion {
        let named = impure.map(\.name).sorted().joined(separator: ", ")
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
