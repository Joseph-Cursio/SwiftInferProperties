import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter

// M10.3 — the domain-inference pass of the lifted-suggestion pipeline.
// Extension-grouped into its own file so `LiftedSuggestionPipeline.swift`
// stays under SwiftLint's file-length cap.
extension LiftedSuggestionPipeline {

    /// M10.3 — for each round-trip suggestion (`templateName == "round-trip"`)
    /// whose `mockGenerator` was populated by the M4.3 fallback,
    /// derives the `(forward, reverse)` pair from the suggestion's
    /// `evidence` (`evidence[0]` is forward, `evidence[1]` is reverse),
    /// looks up the reverse function's call sites in
    /// `domainCallSitesByConsumer`, runs the inferrer with the forward
    /// function's `FunctionSummary`, and rebuilds the suggestion with
    /// `MockGenerator.domainHint` populated. Suggestions without a
    /// mock generator, non-round-trip suggestions, missing pair info,
    /// and inferrer-rejected cases pass through unchanged.
    ///
    /// **Limitation (deferred):** the producer-arg-generatable veto
    /// (M10 plan OD #4) is not currently computed — the pass passes
    /// `producerArgGeneratable: true` unconditionally. The other three
    /// vetoes (throws / async / multi-arg) ARE checked. A `.todo` type
    /// override falls back to the existing `\(typeName).gen()`
    /// surface, matching the M3+ `.todo` posture.
    ///
    /// Exposed for testing via the `applyDomainInferenceForTesting(...)`
    /// `internal` wrapper below; production callers reach this path
    /// through `promote(...)`'s pipeline composition.
    static func applyDomainInference(
        to suggestions: [Suggestion],
        summariesByName: [String: FunctionSummary],
        domainCallSitesByConsumer: [String: [DomainCallSite]]
    ) -> [Suggestion] {
        guard !domainCallSitesByConsumer.isEmpty else {
            return suggestions
        }
        return suggestions.map {
            domainInferred(
                for: $0,
                summariesByName: summariesByName,
                domainCallSitesByConsumer: domainCallSitesByConsumer
            )
        }
    }

    /// The per-suggestion transform applied by `applyDomainInference`'s
    /// `map`. A round-trip suggestion with a two-evidence mock generator
    /// gains a `domainHint` when `DomainInferrer` resolves one; every
    /// other suggestion is returned unchanged. Extracted from the
    /// closure to keep it within SwiftLint's closure-body-length budget.
    private static func domainInferred(
        for suggestion: Suggestion,
        summariesByName: [String: FunctionSummary],
        domainCallSitesByConsumer: [String: [DomainCallSite]]
    ) -> Suggestion {
        guard suggestion.templateName == "round-trip",
              let mockGenerator = suggestion.mockGenerator,
              suggestion.evidence.count == 2 else {
            return suggestion
        }
        let forwardName = bareFunctionName(suggestion.evidence[0].displayName)
        let reverseName = bareFunctionName(suggestion.evidence[1].displayName)
        guard let forwardSummary = summariesByName[forwardName] else {
            return suggestion
        }
        let sites = domainCallSitesByConsumer[reverseName] ?? []
        let pair = RoundTripPair(
            forwardName: forwardName,
            reverseName: reverseName,
            domainTypeName: mockGenerator.typeName
        )
        guard let hint = DomainInferrer.infer(
            pair: pair,
            forwardSummary: forwardSummary,
            sites: sites,
            setupBindings: [:],
            producerArgGeneratable: true
        ) else {
            return suggestion
        }
        let updated = MockGenerator(
            typeName: mockGenerator.typeName,
            argumentSpec: mockGenerator.argumentSpec,
            siteCount: mockGenerator.siteCount,
            preconditionHints: mockGenerator.preconditionHints,
            domainHint: hint
        )
        // Mutate a copy. The field-by-field rebuild this replaces dropped `carrierTypeName` AND
        // `generatorRecipes` — both silently, because the omitted arguments have defaults.
        var copy = suggestion
        copy.mockGenerator = updated
        return copy
    }

    /// Strip parameter labels from an `Evidence.displayName` like
    /// `"encode(_:)"` to recover the bare function name `"encode"` for
    /// `summariesByName` lookup + matching against the M10.3 corpus
    /// call-site map's trailing-identifier keys.
    private static func bareFunctionName(_ displayName: String) -> String {
        if let openParen = displayName.firstIndex(of: "(") {
            return String(displayName[..<openParen])
        }
        return displayName
    }

    /// Internal surface for `DomainInferencePipelineTests`. Forwards
    /// to `applyDomainInference(...)` so the test target can exercise
    /// the M10.3 pass with synthetic inputs without staging the full
    /// M4.3 mock-fallback prerequisite path.
    internal static func applyDomainInferenceForTesting(
        to suggestions: [Suggestion],
        summariesByName: [String: FunctionSummary],
        domainCallSitesByConsumer: [String: [DomainCallSite]]
    ) -> [Suggestion] {
        applyDomainInference(
            to: suggestions,
            summariesByName: summariesByName,
            domainCallSitesByConsumer: domainCallSitesByConsumer
        )
    }
}
