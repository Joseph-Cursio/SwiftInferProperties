import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// `swift-infer discover --docstring-advice` — pairs a documented function's
/// docstring with the law it defines.
///
/// The decision itself is `DocstringAdvisor` in Core, and is unit-tested there.
/// This CLI layer only does the wiring: group the suggestions by function, ask
/// the advisor per documented function, split the answers by whether a seed
/// manifest names the function, and carry each with enough of the function's
/// identity to render it.
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

    /// The two halves of the docstring advisory under `--seeds`. Together they list exactly the
    /// functions an unseeded run advises on.
    struct DocstringAdvice {
        /// Full entries: functions the manifest names, or every function when there is no focus.
        var seeded: [DocstringAdviceItem] = []
        /// Compact entries: documented contracts the manifest does not name. No scaffold.
        var unseeded: [DocstringAdviceItem] = []
    }

    /// Compute docstring advice for the documented functions in the run, split by whether the seed
    /// manifest names them.
    ///
    /// **The parity invariant:** `seeded` and `unseeded` together name exactly the functions a run
    /// without seeds advises on. A manifest decides which functions get the full entry — the
    /// linter's picks stay first, with their scaffolds — and never which get none. Until this
    /// split, the advice for every function the manifest did not name was dropped, and dropped
    /// silently: the advisory went on by default on the strength of a road test run WITHOUT seeds
    /// (8 of 10 hand-keyed kernels), and on SwiftAssist @52823df `--seeds` hid 173 of 286 entries.
    ///
    /// Which seeds focus mirrors `SeedFocus.filter`: the analysable, non-carrier ones.
    ///
    /// - A **kernel** seed does not vouch for its enclosing function. Its symbol names the impure
    ///   method the kernel is trapped in, which is not a function worth a property test.
    /// - An **empty or kernel-only** manifest does not narrow at all, as `SeedFocus` and the
    ///   `--seeds` help text promise: everything goes to `seeded`. It used to suppress every entry.
    /// - A **carrier** seed names a type, not a function, so it adds no key; a carrier-only manifest
    ///   still focuses, and every documented function goes to `unseeded`.
    ///
    /// - Parameters:
    ///   - summaries: every function the scan produced (carries `docComment`).
    ///   - suggestions: the FINAL visible suggestions — the focused list under `--seeds`. Seeded
    ///     advice is decided on it, so a law hidden by the tier cut does not count as "already
    ///     served", and the synthesized determinism law stays available as a scaffold source.
    ///   - unfocusedSuggestions: what a run without seeds would show (`pipeline.suggestions`).
    ///     Unseeded advice is decided on it, and must be: the focus drops a lifted law whose
    ///     subject the scan declared, so on the focused list a function the advisor would answer
    ///     from its lifted law (arm 2) can fall through to "already served" (arm 5) and vanish.
    ///   - seedManifest: the manifest, or `nil` for no focus.
    static func docstringAdvice(
        summaries: [FunctionSummary],
        suggestions: [Suggestion],
        unfocusedSuggestions: [Suggestion],
        seedManifest: SeedManifest?
    ) -> DocstringAdvice {
        let seedKeys = docstringSeedKeys(seedManifest)
        let focused = suggestionsByFunction(suggestions)
        let unfocused = suggestionsByFunction(unfocusedSuggestions)

        var advice = DocstringAdvice()
        var seen: Set<String> = []
        for summary in summaries {
            let key = genericLawKey(file: summary.location.file, symbol: summary.name)
            guard !seen.contains(key), summary.docComment != nil else { continue }
            if seedKeys?.contains(key) ?? true {
                guard let item = adviceItem(
                    for: summary, suggestions: focused[key] ?? [], withScaffold: true
                ) else { continue }
                advice.seeded.append(item)
            } else {
                guard let item = adviceItem(
                    for: summary, suggestions: unfocused[key] ?? [], withScaffold: false
                ) else { continue }
                advice.unseeded.append(item)
            }
            seen.insert(key)
        }
        return advice
    }

    /// The function keys the manifest focuses docstring advice on, or `nil` for no focus — the
    /// same seeds `SeedFocus.filter` joins on.
    private static func docstringSeedKeys(_ seedManifest: SeedManifest?) -> Set<String>? {
        seedManifest.flatMap { manifest in
            let analysable = manifest.analysableSeeds
            // Empty or kernel-only: nothing to focus on, so no focus.
            guard !analysable.isEmpty else { return nil }
            return Set(
                analysable
                    .filter { $0.kind != .carrier }
                    .map { genericLawKey(file: $0.file, symbol: $0.symbol) }
            )
        }
    }

    /// Group suggestions by the function each speaks to. A pair template (round-trip,
    /// commutativity) speaks to both halves, so each evidence entry contributes.
    private static func suggestionsByFunction(_ suggestions: [Suggestion]) -> [String: [Suggestion]] {
        var grouped: [String: [Suggestion]] = [:]
        for suggestion in suggestions {
            for evidence in suggestion.evidence {
                let key = genericLawKey(
                    file: evidence.location.file,
                    symbol: functionBaseName(evidence.displayName)
                )
                grouped[key, default: []].append(suggestion)
            }
        }
        return grouped
    }

    /// The advice for one documented function, or `nil` when the advisor has none. The runnable
    /// scaffold is attached only when `withScaffold` — the compact block prints none.
    private static func adviceItem(
        for summary: FunctionSummary,
        suggestions: [Suggestion],
        withScaffold: Bool
    ) -> DocstringAdviceItem? {
        guard let advisory = DocstringAdvisor.advisory(
            forFunctionWith: summary.docComment,
            suggestions: suggestions
        ) else { return nil }
        return DocstringAdviceItem(
            displayName: displayName(for: summary),
            signature: signature(for: summary),
            location: summary.location,
            advisory: advisory,
            runnableScaffold: withScaffold
                ? referenceOracleScaffold(for: summary, advisory: advisory, suggestions: suggestions)
                : nil
        )
    }

    /// Templates whose reference-definition advisory carries a runnable
    /// oracle stub: a `predicate` (the docstring IS the boolean law) and a
    /// `comparator` (the docstring is the ordering KEY the strict-weak-ordering
    /// law can't capture). Both are Bool-returning functions the emitter handles
    /// uniformly — a comparator is just a two-argument predicate on ordering.
    private static let oracleStubTemplates: Set<String> = ["predicate", "comparator"]

    /// The runnable reference-oracle scaffold for a documented function, or `nil`
    /// when it does not apply. Three shapes: a `predicate` / `comparator`
    /// reference definition (return `Bool`), and the determinism-fallback
    /// contract (the return is the value type, the reference a from-the-spec
    /// re-implementation). Handles any arity — scalar draw for one parameter,
    /// tuple for several.
    private static func referenceOracleScaffold(
        for summary: FunctionSummary,
        advisory: DocstringAdvisory,
        suggestions: [Suggestion]
    ) -> String? {
        guard !summary.parameters.isEmpty, let docComment = summary.docComment else {
            return nil
        }

        let returnTypeText: String
        let sourceSuggestion: Suggestion?
        switch advisory {
        case let .referenceDefinition(reference):
            guard oracleStubTemplates.contains(reference.template), !reference.fromLiftedTest else {
                return nil
            }
            returnTypeText = "Bool"
            sourceSuggestion = suggestions.first { $0.templateName == reference.template }

        case .fallbackContract, .complementaryContract:
            // The docstring is the contract the templates could not name — either because
            // nothing role-entailed fired at all, or because what fired is unreachable by
            // realistic input and so checks something else. Both want the same scaffold: make
            // the sentence runnable as a from-the-spec reference implementation, which needs a
            // concrete, non-Void return to compare against.
            guard let returned = summary.returnTypeText, returned != "Void", returned != "()" else {
                return nil
            }
            returnTypeText = returned
            // Any surviving pick (determinism / red herring) gives a stable seed
            // and generator source; the fallback fired because none was owed.
            sourceSuggestion = suggestions.first
        }
        guard let suggestion = sourceSuggestion else {
            return nil
        }

        let arguments = summary.parameters.map { parameter in
            LiftedTestEmitter.ReferenceOracleArgument(
                parameter: parameter,
                generator: InteractiveTriage.chooseGenerator(for: suggestion, typeName: parameter.typeText)
            )
        }
        return LiftedTestEmitter.referenceOracle(
            funcName: summary.name,
            arguments: arguments,
            returnTypeText: returnTypeText,
            docComment: docComment,
            seed: SamplingSeed.derive(from: suggestion.identity)
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
