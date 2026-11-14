import SwiftInferCore
import SwiftInferTemplates

// Call resolution for `emptiness-agreement` (#701), in its own file because
// `+CallResolution` holds the shared switch and this law's refusals need their
// rationale beside them. Reached through `resolveTwoFunctionCalls`, so it costs
// `resolveFunctionCalls` no branch.
extension SwiftInferCommand.Verify {

    /// Resolve the two members of `value.p == (value.m > 0)` — or `== 0` for `isEmpty`.
    ///
    /// **The expressions are member spellings, not callable references**: `hasIssues`,
    /// `totalIssueCount()`, which the composer writes after `value.`. The template admits only
    /// instance members that take no arguments and neither mutate, throw nor suspend
    /// (`EmptinessAgreementPairing.isArgumentFreeMember`), so both are read off one generated
    /// value and there is nothing to apply. The renderer gets the bare names.
    ///
    /// Three refusals, all `staleIndexEntry`, because each means the entry was written with less
    /// than this law needs and re-indexing is the remedy:
    /// - **no measure name** — `secondaryFunctionName` was persisted for this template only
    ///   from #701, so every earlier entry lacks it;
    /// - **no measure shape** — `Evidence.displayName` reads `count()` for a property and a
    ///   method alike, and the two have no shared spelling: `value.count()` on a property and
    ///   `value.count` on a method both fail to compile. An index old enough to lack the
    ///   PRIMARY's `isComputedProperty` (which decodes as `false`, not `nil`) lacks this column
    ///   too, so this check also stands guard for the predicate's spelling;
    /// - **the names no longer pair** — the pairing rules, run today, would not propose the row,
    ///   and without a polarity there is no law to state. Unreachable from an index this binary
    ///   wrote.
    static func resolveEmptinessAgreementCalls(entry: SemanticIndexEntry) throws -> ResolvedCalls {
        let template = TemplateName.emptinessAgreement.rawValue
        let primary = entry.primaryFunctionName
        guard let measureName = entry.secondaryFunctionName else {
            throw VerifyError.staleIndexEntry(
                template: template,
                primary: primary,
                reason: "it records no count to compare the predicate with "
                    + "(`secondaryFunctionName`, persisted for this template from 2026-11-13)"
            )
        }
        guard let measureShape = entry.secondaryMemberShape else {
            throw VerifyError.staleIndexEntry(
                template: template,
                primary: primary,
                reason: "it does not record whether '\(measureName)' is a computed property or a "
                    + "method (`secondaryMemberShape`, added 2026-11-13)"
            )
        }
        let predicateBare = RoundTripPairResolver.stripParameterLabels(primary)
        let measureBare = RoundTripPairResolver.stripParameterLabels(measureName)
        guard EmptinessAgreementPairing.polarity(predicate: predicateBare, measure: measureBare) != nil else {
            throw VerifyError.staleIndexEntry(
                template: template,
                primary: primary,
                reason: "'\(predicateBare)' and '\(measureBare)' no longer pair under the naming "
                    + "rules, so no polarity — `> 0` or `== 0` — can be read from them"
            )
        }
        return ResolvedCalls(
            expressions: [
                MemberAccessShape(isComputedProperty: entry.isComputedProperty).spelling(of: predicateBare),
                measureShape.spelling(of: measureBare),
            ],
            rendererForwardName: predicateBare,
            rendererInverseName: measureBare
        )
    }
}
