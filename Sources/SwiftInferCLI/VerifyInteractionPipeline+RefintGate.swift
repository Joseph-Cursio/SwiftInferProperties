import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Cycle 139 — referential-integrity `Identifiable` gate. The refint
/// verifier emits `state.collection.contains { $0.id == state.selected }`,
/// so the collection's element type must host an `id`. For an un-curated
/// corpus whose element type is NOT Identifiable, the synthesized stub fails
/// to `swift build` and surfaces as `architectural-coverage-pending` only
/// *after* a wasted ~minute-long build. This gate detects that case
/// **before** building — via the cycle-139 `IdentifiableResolver` over the
/// corpus's `TypeDecl`s — and returns a clean, disclosed skip.
///
/// Conservative by design (see `IdentifiableResolver`): it skips only when
/// the element type is *provably* non-Identifiable (declared in the corpus
/// with neither `Identifiable` conformance nor an `id` member). An external
/// type stays `.unknown` → the build proceeds (pre-cycle-139 behavior, no
/// regression).
extension VerifyInteractionPipeline {

    /// Apply the gate: when it fires, record the disclosed skip (if
    /// persisting) and return it so the caller short-circuits before the
    /// build; otherwise `nil` so the caller proceeds. Extracted from
    /// `runWithInvariant` to keep that file under SwiftLint's `file_length`.
    static func applyRefintIdentifiabilityGate(
        invariant: InteractionInvariantSuggestion,
        candidate: ReducerCandidate,
        target: String,
        persistEvidence: Bool,
        workingDirectory: URL
    ) -> InteractionVerifyOutcomeParser.Result? {
        guard let skip = refintIdentifiabilitySkip(
            invariant: invariant, candidate: candidate,
            target: target, workingDirectory: workingDirectory
        ) else { return nil }
        if persistEvidence {
            recordEvidence(invariant: invariant, result: skip, workingDirectory: workingDirectory)
        }
        return skip
    }

    /// Returns a pre-build `architectural-coverage-pending` skip when the
    /// refint invariant's collection element type is provably
    /// non-Identifiable; `nil` for non-refint invariants or when the element
    /// is Identifiable / unknown (the build proceeds).
    static func refintIdentifiabilitySkip(
        invariant: InteractionInvariantSuggestion,
        candidate: ReducerCandidate,
        target: String,
        workingDirectory: URL
    ) -> InteractionVerifyOutcomeParser.Result? {
        guard invariant.family == .referentialIntegrity else { return nil }
        let directory = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        guard let elementType = refintElementType(
            invariant: invariant, candidate: candidate, directory: directory
        ) else { return nil }
        guard let scanned = try? FunctionScanner.scanCorpus(directory: directory) else { return nil }
        let resolver = IdentifiableResolver(typeDecls: scanned.typeDecls)
        guard resolver.classify(typeText: elementType) == .notIdentifiable else { return nil }
        return InteractionVerifyOutcomeParser.Result(
            outcome: .architecturalCoveragePending,
            detail: "referential-integrity verify skipped: element type `\(elementType)` is not "
                + "Identifiable (no `id` member) — the `$0.id` reference in the predicate "
                + "cannot compile"
        )
    }

    /// Recover the collection element type for `invariant` by re-running the
    /// refint witness detector over the candidate's State and matching the
    /// witness whose selected + collection property names appear in the
    /// invariant's predicate. (The template's `makePredicate` is
    /// module-internal, so we match on the property-name substrings the
    /// predicate is built from — the `.contains` anchor disambiguates a
    /// collection name that prefixes another.)
    private static func refintElementType(
        invariant: InteractionInvariantSuggestion,
        candidate: ReducerCandidate,
        directory: URL
    ) -> String? {
        guard let witnesses = try? ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: candidate.stateQualifiedName, in: directory
        ) else { return nil }
        return witnesses.first { witness in
            invariant.predicate.contains("state.\(witness.collectionPropertyName).contains")
                && invariant.predicate.contains("state.\(witness.selectedPropertyName)")
        }?.elementTypeName
    }
}
