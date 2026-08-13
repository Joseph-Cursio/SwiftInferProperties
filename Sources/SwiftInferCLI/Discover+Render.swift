import Foundation
import SwiftInferCore

/// `swift-infer discover` orchestration helpers — rendering the surviving
/// suggestions and loading persisted `verify` evidence. Extracted from
/// `SwiftInferCommand.swift` so the command file stays under SwiftLint's
/// file- and type-body-length caps; behavior is unchanged.
extension SwiftInferCommand.Discover {

    /// V1.89 lint pass — render branch extracted from `Discover.run`
    /// so the orchestrator body stays under SwiftLint's 50-line cap.
    /// V1.64.C annotation behavior unchanged: when `evidenceByIdentity`
    /// is empty, blocks render byte-identically to the pre-v1.64 output.
    /// - Parameter coverage: what PropertyLawKit covers on this corpus. Rendered as the first
    ///   line, **always**, including when it is zero. A `discover` count read on its own is
    ///   close to meaningless — a perfect kit would leave nothing to discover, so `0
    ///   suggestions.` alone is total success and total failure spelled identically. Defaulted
    ///   only so the non-discover callers (drift, interactive) compile unchanged.
    static func renderAndWrite(
        visible: [Suggestion],
        statsOnly: Bool,
        evidenceByIdentity: [String: VerifyEvidence],
        effectAnnotations: [EffectAnnotationAdvice] = [],
        docstringAdvice: [DocstringAdviceItem] = [],
        refutedLaws: [Suggestion] = [],
        coverage: CoverageSummary = CoverageSummary(
            lawCount: 0, carrierCount: 0, evidenceState: .noEvidence
        ),
        output: any DiscoverOutput
    ) {
        // V1.147 — enrich each candidate's explainability with stdlib-anchor
        // provenance (proven analog / known trap). Score-neutral; fires only
        // for catalogued stdlib carriers, so custom-type output is unchanged.
        let anchored = visible.map { StdlibAnchor.enriched($0) }
        var rendered: String
        if statsOnly {
            // The same evidence the full renderer gets. Until v1.149 this call passed none,
            // so `--stats-only` could not print `Verified` and reported every
            // execution-backed row as `Strong` — see `tierBreakdown`.
            rendered = SuggestionRenderer.renderStats(
                anchored,
                verifyEvidenceByIdentity: evidenceByIdentity
            )
        } else {
            rendered = SuggestionRenderer.render(
                anchored,
                verifyEvidenceByIdentity: evidenceByIdentity
            )
        }

        // Separate advisory channel — appended (never property-test suggestions)
        // only in full output and only when there is advice, so stats / empty /
        // advice-free output is byte-identical to before. `DiscoverOutput.write`
        // replaces rather than appends, so the block joins the rendered string
        // here and a single `write` carries both.
        // **Before the advisory blocks and OUTSIDE the `statsOnly` guard, both deliberately.**
        // A refutation is the only execution-backed output this tool produces, and it is the
        // one thing a reader must not miss — `--stats-only` is what CI reads, and hiding a
        // measured counterexample from CI is the whole defect. Advisories are suggestions
        // about what to write; this is a result.
        let refutationBlock = RefutationRenderer.render(refutedLaws)
        if !refutationBlock.isEmpty {
            rendered += "\n\n" + refutationBlock
        }
        if !statsOnly {
            let adviceBlock = EffectAnnotationRenderer.render(effectAnnotations)
            if !adviceBlock.isEmpty {
                rendered += "\n\n" + adviceBlock
            }
            let docstringBlock = DocstringAdvisoryRenderer.render(docstringAdvice)
            if !docstringBlock.isEmpty {
                rendered += "\n\n" + docstringBlock
            }
        }

        // First line, before the count, on stdout. Prepended here in the CLI layer rather
        // than inside `SuggestionRenderer` on purpose: the renderer's output is pinned
        // byte-for-byte by golden tests (`GeneratorSelectionIntegrationTests`), and those
        // goldens are about a *suggestion's* rendering, which this is not part of.
        let headline = CoverageHeadline.line(
            suggestionCount: visible.count,
            lawCount: coverage.lawCount,
            carrierCount: coverage.carrierCount,
            evidenceState: coverage.evidenceState
        )
        output.write(headline + "\n\n" + rendered)
    }

    /// `--interactive` and `--update-baseline` are mutually exclusive; the early
    /// return in the interactive branch enforces it, so this only warns. Extracted
    /// from `run` to keep its body under the 50-line cap.
    static func warnIfConflictingModes(
        interactive: Bool,
        updateBaseline: Bool,
        diagnostics: any DiagnosticOutput
    ) {
        if interactive, updateBaseline {
            diagnostics.writeDiagnostic(
                "warning: --interactive and --update-baseline are mutually exclusive; "
                    + "--update-baseline ignored for this run"
            )
        }
    }

    /// V1.67 — load persisted `swift-infer verify` evidence so it
    /// feeds the pipeline's scoring AND its visibility filter:
    /// `bothPass` raises the score (and can lift a pick past the
    /// visibility threshold), `defaultFails` vetoes → `.suppressed`
    /// → dropped by the pipeline's own filter. The returned map
    /// is reused for the V1.64.C render-time annotation.
    ///
    /// V1.89 lint pass — extracted from `Discover.run` so the
    /// orchestrator body stays under SwiftLint's 50-line cap.
    /// Both executed-evidence sources, loaded together. PropertyLawKit's verdicts are absent
    /// in the normal case, which leaves inference's standing assumption intact — that `==` is
    /// sound, because checking that is what the Equatable laws are for.
    static func loadEvidence(
        directory: URL,
        diagnostics: any DiagnosticOutput
    ) -> DiscoverEvidenceInputs {
        DiscoverEvidenceInputs(
            verifyByIdentity: loadVerifyEvidenceMap(directory: directory, diagnostics: diagnostics),
            // The sibling call already threads diagnostics; this one did not, so an
            // unreadable kit-evidence log reached the reader as "no evidence".
            kit: KitEvidenceStore.load(
                startingFrom: directory,
                diagnostic: diagnostics.writeDiagnostic
            )
        )
    }

    static func loadVerifyEvidenceMap(
        directory: URL,
        diagnostics: any DiagnosticOutput
    ) -> [String: VerifyEvidence] {
        let evidenceResult = VerifyEvidenceStore.load(startingFrom: directory)
        for warning in evidenceResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        return Dictionary(
            evidenceResult.log.records.map { ($0.identityHash, $0) }
        ) { _, latest in latest }
    }
}
