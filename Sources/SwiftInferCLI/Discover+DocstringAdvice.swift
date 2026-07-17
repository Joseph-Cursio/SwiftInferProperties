import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// `swift-infer discover --docstring-advice` — pairs a documented function's
/// docstring with the law it defines.
///
/// The decision itself is `DocstringAdvisor` in Core, and is unit-tested there.
/// This CLI layer only does the wiring: group the final suggestions by function,
/// ask the advisor per documented function, and carry the answer with enough of
/// the function's identity to render it.
extension SwiftInferCommand.Discover {

    /// A docstring advisory bound to the function it speaks to, ready to render.
    struct DocstringAdviceItem {
        let displayName: String
        let signature: String
        let location: SourceLocation
        let advisory: DocstringAdvisory
        /// B25 (issue #1) — for a single-parameter documented predicate, the
        /// runnable reference-oracle scaffold: the `<name>_reference` stub plus
        /// the predicate-vs-oracle property. `nil` for every other case. The
        /// reader fills the one boolean the docstring dictates; the generator
        /// then finds the input where the code disagrees with its documentation.
        let runnableScaffold: String?
    }

    /// Compute docstring advice for the documented functions in the run.
    ///
    /// - Parameters:
    ///   - summaries: every function the scan produced (carries `docComment`).
    ///   - suggestions: the FINAL visible suggestions — advice reflects exactly
    ///     what the reader is shown, so a law hidden by the tier cut does not
    ///     count as "already served."
    ///   - seedManifest: when present, advice is restricted to seeded functions,
    ///     mirroring the generic-law fallback — a seed is the linter vouching
    ///     that the function is worth property-testing. With no manifest every
    ///     documented function is eligible.
    static func docstringAdvice(
        summaries: [FunctionSummary],
        suggestions: [Suggestion],
        seedManifest: SeedManifest?
    ) -> [DocstringAdviceItem] {
        let seedKeys = seedManifest.map { manifest in
            Set(manifest.seeds.map { genericLawKey(file: $0.file, symbol: $0.symbol) })
        }

        // Group the final suggestions by the function each speaks to. A pair
        // template (round-trip, commutativity) speaks to both halves, so each
        // evidence entry contributes.
        var suggestionsByFunction: [String: [Suggestion]] = [:]
        for suggestion in suggestions {
            for evidence in suggestion.evidence {
                let key = genericLawKey(
                    file: evidence.location.file,
                    symbol: functionBaseName(evidence.displayName)
                )
                suggestionsByFunction[key, default: []].append(suggestion)
            }
        }

        var items: [DocstringAdviceItem] = []
        var seen: Set<String> = []
        for summary in summaries {
            let key = genericLawKey(file: summary.location.file, symbol: summary.name)
            guard !seen.contains(key) else { continue }
            if let seedKeys, !seedKeys.contains(key) { continue }
            guard summary.docComment != nil else { continue }
            guard let advisory = DocstringAdvisor.advisory(
                forFunctionWith: summary.docComment,
                suggestions: suggestionsByFunction[key] ?? []
            ) else { continue }
            seen.insert(key)
            items.append(
                DocstringAdviceItem(
                    displayName: displayName(for: summary),
                    signature: signature(for: summary),
                    location: summary.location,
                    advisory: advisory,
                    runnableScaffold: predicateScaffold(
                        for: summary,
                        advisory: advisory,
                        suggestions: suggestionsByFunction[key] ?? []
                    )
                )
            )
        }
        return items
    }

    /// The runnable reference-oracle scaffold for a single-parameter documented
    /// predicate, or `nil` when it does not apply. Fires only when the advisory
    /// is a `predicate` reference definition (the case the verify pipeline
    /// reports as `unsupported-template: predicate` for lack of an oracle) and
    /// the function takes exactly one parameter. Multi-parameter predicates are
    /// a follow-on — the sample would need a tuple draw.
    private static func predicateScaffold(
        for summary: FunctionSummary,
        advisory: DocstringAdvisory,
        suggestions: [Suggestion]
    ) -> String? {
        guard case let .referenceDefinition(reference) = advisory,
              reference.template == "predicate",
              !reference.fromLiftedTest,
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              let docComment = summary.docComment,
              let predicateSuggestion = suggestions.first(where: { $0.templateName == "predicate" })
        else {
            return nil
        }
        return LiftedTestEmitter.predicateReferenceOracle(
            funcName: summary.name,
            parameter: parameter,
            docComment: docComment,
            seed: SamplingSeed.derive(from: predicateSuggestion.identity),
            generator: InteractiveTriage.chooseGenerator(
                for: predicateSuggestion,
                typeName: parameter.typeText
            )
        )
    }

    /// `name(label:)` — the labelled display form, matching the evidence renderer.
    private static func displayName(for summary: FunctionSummary) -> String {
        let labels = summary.parameters.map { "\($0.label ?? "_"):" }.joined()
        return "\(summary.name)(\(labels))"
    }

    private static func signature(for summary: FunctionSummary) -> String {
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        let returnType = summary.returnTypeText ?? "Void"
        let effectMarker = summary.isAsync ? " async" : ""
        return "(\(paramTypes))\(effectMarker) -> \(returnType)"
    }
}
