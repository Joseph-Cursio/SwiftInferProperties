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
        /// B25 (issue #1) — the runnable reference-oracle scaffold: the `<name>_reference` stub
        /// plus the property checking the function against it, for a predicate, a comparator or
        /// a fallback / complementary contract of any arity. The reader fills the one definition
        /// the docstring dictates; the generator then finds the input where the code disagrees
        /// with its documentation. `nil` when the advisory offers none, or when it cannot compile
        /// and `oracleDecline` says why.
        let runnableScaffold: String?

        /// Why no scaffold is printed although the advisory offers one — the call cannot be
        /// spelled, the subject is `private`, nothing derives an argument, and so on — rendered
        /// as `── no runnable reference oracle: <reason>`. At most one of this and
        /// `runnableScaffold` is set.
        var oracleDecline: String?
    }

    /// The two halves of the docstring advisory under `--seeds`. Together they list the functions
    /// an unseeded run advises on — near-exactly; see `docstringAdvice` for what that rests on.
    struct DocstringAdvice {
        /// Full entries: functions the manifest names as analysable seeds, or every function when
        /// there is no focus.
        var seeded: [DocstringAdviceItem] = []
        /// Compact entries: every other documented contract, including a function only a kernel
        /// seed names. No scaffold.
        var unseeded: [DocstringAdviceItem] = []
    }

    /// Compute docstring advice for the documented functions in the run, split by whether the seed
    /// manifest names them as functions to analyse.
    ///
    /// **The parity rule:** a manifest decides which functions get the full entry — the linter's
    /// picks stay first, with their scaffolds — and never which get none, so `seeded` and
    /// `unseeded` together name the functions a run without seeds advises on. Until this split,
    /// the advice for every function the manifest did not name was dropped, and dropped silently:
    /// the advisory went on by default on the strength of a road test run WITHOUT seeds (8 of 10
    /// hand-keyed kernels), and on SwiftAssist @52823df `--seeds` hid 173 of 286 entries.
    ///
    /// **Near-exact, and not guaranteed here.** The split drops nothing, so the halves match a
    /// plain run whenever the advisor gives each function the same arm with and without seeds —
    /// which rests on code outside this function. As that code stands the arm cannot move:
    ///
    /// - the manifest reaches the pipeline only through `SeedEffectResolver`, whose effects feed
    ///   the `idempotence` template (a conjecture, which no arm reads), and
    ///   `SeedRestrictionResolver`, whose access reasons feed caveats and the determinism fallback;
    /// - the tier cut shows every role-entailed law it does not suppress as refuted, and the focus
    ///   keeps them all (`keepRoleEntailedLaws`), so nothing the focus, `promoteTierHiddenLaws` or
    ///   `guardFinalAnswer` does can add or drop one.
    ///
    /// Rendered text can still differ — a red herring, or the suggestion a scaffold draws from. On
    /// SwiftAssist @52823df the halves matched a plain run name for name: 97 full + 189 compact =
    /// 286.
    ///
    /// Which seeds focus mirrors `SeedFocus.filter`: the analysable, non-carrier ones.
    ///
    /// - A **kernel** seed does not vouch for its enclosing function. Its symbol names the impure
    ///   method the kernel is trapped in, which is not a function worth a property test.
    /// - An **empty or kernel-only** manifest does not narrow at all, as `SeedFocus` and the
    ///   `--seeds` help text promise: everything goes to `seeded`. An empty manifest used to
    ///   suppress every entry, and a kernel-only one narrowed the advice to the kernels' hosts.
    /// - A **carrier** seed names a type, not a function, so it adds no key; a carrier-only manifest
    ///   still focuses, and every documented function goes to `unseeded`.
    ///
    /// - Parameters:
    ///   - summaries: every function the scan produced (carries `docComment`).
    ///   - suggestions: the FINAL visible suggestions — the focused list under `--seeds`. Seeded
    ///     advice is decided on it, so a law hidden by the tier cut does not count as "already
    ///     served", and the synthesized determinism law stays available as a scaffold source.
    ///   - unfocusedSuggestions: what a run without seeds would show (`pipeline.suggestions`).
    ///     Unseeded advice is decided on it, so each compact entry carries the advisory a plain
    ///     run computes. Today the focused list would give every unseeded function the same ARM:
    ///     it holds the same role-entailed laws (see above), and arm 2 never fires through this
    ///     join — a lifted law's evidence names its test file (`LiftedSuggestionPromotion.site`),
    ///     never the production function. The focus drops only conjectures, which a fallback
    ///     names as red herrings and the compact block does not print. It stops being cosmetic if
    ///     lifted laws ever join their subject: the focus drops a lifted law on a declared,
    ///     unseeded subject, so a function answered from arm 2 would fall to arm 5 on the focused
    ///     list and vanish.
    ///   - seedManifest: the manifest, or `nil` for no focus.
    ///   - oracleContext: the scan the reference oracle resolves generators and gates over;
    ///     `.unscanned` resolves no project type, so such an oracle is declined.
    static func docstringAdvice(
        summaries: [FunctionSummary],
        suggestions: [Suggestion],
        unfocusedSuggestions: [Suggestion],
        seedManifest: SeedManifest?,
        oracleContext: ReferenceOracleContext = .unscanned
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
                    for: summary, suggestions: focused[key] ?? [], oracleContext: oracleContext
                ) else { continue }
                advice.seeded.append(item)
            } else {
                guard let item = adviceItem(
                    for: summary, suggestions: unfocused[key] ?? [], oracleContext: nil
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

    /// The advice for one documented function, or `nil` when the advisor has none. The reference
    /// oracle is attached only with an `oracleContext` — the compact block prints none.
    private static func adviceItem(
        for summary: FunctionSummary,
        suggestions: [Suggestion],
        oracleContext: ReferenceOracleContext?
    ) -> DocstringAdviceItem? {
        guard let advisory = DocstringAdvisor.advisory(
            forFunctionWith: summary.docComment,
            suggestions: suggestions
        ) else { return nil }
        let oracle = oracleContext.flatMap { context in
            referenceOracleOutcome(for: summary, advisory: advisory, suggestions: suggestions, context: context)
        }
        return DocstringAdviceItem(
            displayName: displayName(for: summary),
            signature: signature(for: summary),
            location: summary.location,
            advisory: advisory,
            runnableScaffold: oracle?.scaffold,
            oracleDecline: oracle?.decline
        )
    }

    /// `name(label:)` — the labelled display form, matching the evidence renderer.
    static func displayName(for summary: FunctionSummary) -> String {
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
