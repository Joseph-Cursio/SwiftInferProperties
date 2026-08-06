import Foundation
import SwiftEffectInference

/// Applies effects a linter resolved to the summaries this tool scored.
///
/// The sibling of `EffectResolver`, and the division of labour is the point.
/// `EffectResolver` re-parses the corpus and walks bodies itself, which costs a
/// second pass and is therefore opt-in behind a flag. This does the same job for
/// free when a seed manifest is present, because the linter already paid.
///
/// **What it adds that the local pass cannot.** `EffectResolver` runs
/// `applyBodyInference(multiHop: false)` — one hop — against a 30-second budget
/// it must fit inside §13's 2-second discover budget. A linter running ahead of
/// the pipeline has no such constraint and resolves to a fixed point across
/// every file. So a `@NonIdempotent` three calls down, which the local pass
/// structurally cannot see, arrives here already resolved.
///
/// **What it deliberately refuses.** A chain that bottoms out on a **name
/// guess**, and one whose anchor the producer did not state. See
/// `SeedEffect.carriesEnoughEvidenceToDemote` — the short version is that this
/// package has already decided, in `EffectResolver`, that a veto built on a name
/// guess is worse than no veto.
///
/// **This said "only `provenance: declared` is acted on" until 2026-08-06, and
/// the widening is the whole point of the field that replaced it.** The old rule
/// withheld *every* upward chain, because `provenance` names only the final hop
/// and an upward tier could bottom out on a guess without saying so. The
/// producer now emits `anchor` (SwiftProjectLint `a5795819`), so a multi-hop,
/// cross-file chain in which every justifying step was a human annotation is
/// distinguishable from a guessed one — and that chain is precisely what this
/// resolver exists for, since the local pass runs **one hop** against §13's
/// 2-second ceiling and structurally cannot see it.
public enum SeedEffectResolver {

    /// Fills `inferredEffect` from the manifest on every summary a seed names.
    /// Returns the summaries in input order.
    ///
    /// Written into `inferredEffect` rather than `declaredEffect` because that
    /// is what the manifest's `resolved` field *is*: a statement about what a
    /// body reaches, not about what its author wrote on it. It is the same claim
    /// `EffectResolver` makes, sourced better. Putting it in `declaredEffect`
    /// would promote a callee's annotation into a claim by the caller, and
    /// `IdempotenceTemplate` would then veto rather than demote — turning a
    /// stronger *source* into a stronger *verdict*, which does not follow.
    ///
    /// **Unlike `EffectResolver`, this fills `inferredEffect` even when the
    /// function declares its own effect — and that case is the entire point.**
    ///
    /// The first draft guarded on `declaredEffect == nil`, copying the local
    /// resolver, and was therefore dead code: every `idempotency` seed names a
    /// function that *is* annotated, because an unannotated function cannot
    /// violate an idempotency claim it never made. The guard and the seed
    /// population were mutually exclusive, and only an end-to-end run against a
    /// real manifest showed it.
    ///
    /// The guard is right for `EffectResolver`, whose inference is a weaker
    /// signal that must not dilute a declaration. Here the two are not competing
    /// descriptions of one function — they are a **claim and its refutation**.
    /// `declaredEffectSignal` reads `@Idempotent` as +15 corroboration; the
    /// manifest says a linter followed the call graph and found the body reaches
    /// non-idempotent work. Both should be heard: the annotation is real
    /// evidence, and so is the contradiction. `inferredRetryHostileCallee` at
    /// -45 against that +15 lands the suggestion at a net demotion with both
    /// reasons attached, which is the honest rendering of "the author says yes,
    /// their own call graph says no".
    ///
    /// Suppressing either one would be worse. Dropping the annotation hides that
    /// someone made a claim; dropping the refutation restates a claim the code
    /// contradicts.
    public static func resolve(
        summaries: [FunctionSummary],
        manifest: SeedManifest,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> [FunctionSummary] {
        // Reported unconditionally, not only when nothing was actionable. A
        // manifest usually carries a mix, and announcing the withheld ones only
        // in the all-withheld case would hide them behind whatever *did* apply —
        // which is precisely when a reader is least likely to wonder what else
        // was in the file.
        reportWithheld(manifest: manifest, diagnostic: diagnostic)
        let actionable = manifest.seeds.filter {
            $0.effect?.carriesEnoughEvidenceToDemote == true
        }
        guard !actionable.isEmpty else { return summaries }
        var effectByKey: [String: SeedEffect] = [:]
        for seed in actionable {
            guard let effect = seed.effect else { continue }
            // Last writer wins, which only matters when one manifest carries two
            // seeds for one `(file, symbol)` — and then the tiers agree, because
            // they came from one analysis of one function.
            effectByKey[joinKey(file: seed.file, symbol: seed.symbol)] = effect
        }

        var applied = 0
        let updated = summaries.map { summary -> FunctionSummary in
            let key = joinKey(file: summary.location.file, symbol: summary.name)
            guard let effect = effectByKey[key],
                  EffectResolver.carriesInformationUpward(effect.resolved.asEffect)
            else {
                return summary
            }
            applied += 1
            return summary.withInferredEffect(effect.resolved.asEffect)
        }
        if applied > 0 {
            diagnostic(
                "applied \(applied) linter-resolved effect(s) from the seed manifest — "
                    + "cross-file and multi-hop, which the local one-hop pass cannot reach"
            )
        }
        return updated
    }

    /// `(file basename, symbol)`, matching `SeedFocus` and `SeedRestrictionResolver`.
    ///
    /// **This keyed on the bare symbol name until 2026-08-06, and widening
    /// `carriesEnoughEvidenceToDemote` is what made that reachable.** Nothing in
    /// this repository carried a `declared`-provenance effect, so nothing was
    /// ever applied and the loose join cost nothing; admitting
    /// declaration-anchored upward chains applied 3 seeds and the run reported
    /// **5**. The extra two are functions merely *named* `record` —
    /// `ViewModelVerifyEvidence.record` and `RefactorBridgeAccumulator.record` —
    /// which the manifest never named and which would have inherited a
    /// `nonIdempotent` tier resolved for a different function in a different
    /// file. That is a **false demotion**, the precision failure this package is
    /// built against, and it is exactly what a name-only join produces in a
    /// codebase where `record`, `resolve` and `apply` are everywhere.
    ///
    /// Found by running the change rather than by reading it: the count in the
    /// diagnostic did not match the count of seeds.
    static func joinKey(file: String, symbol: String) -> String {
        "\(URL(fileURLWithPath: file).lastPathComponent)::\(symbol)"
    }

    /// Say what was dropped and why.
    ///
    /// A manifest can carry effects this resolver refuses, and refusing them
    /// silently would look identical to a producer that emitted none — the same
    /// confident-zero shape the seed pipeline keeps rediscovering. The reader
    /// should be able to tell "the linter said nothing" from "the linter said
    /// something I am not willing to score."
    private static func reportWithheld(manifest: SeedManifest, diagnostic: (String) -> Void) {
        let withheld = manifest.seeds.compactMap(\.effect).filter {
            !$0.carriesEnoughEvidenceToDemote
        }
        guard !withheld.isEmpty else { return }
        let downward = withheld.filter { $0.provenance == .inferredDownward }.count
        let guessAnchored = withheld.filter { $0.anchor == .heuristic }.count
        let unanchored = withheld.filter {
            $0.provenance == .inferredUpward && $0.anchor == nil
        }.count
        diagnostic(
            "withheld \(withheld.count) linter-resolved effect(s) as evidence "
                + "(\(downward) inferred-downward, \(guessAnchored) upward but anchored on a name "
                + "guess, \(unanchored) upward with no anchor stated): this tool does not veto on "
                + "names, and a chain whose anchor the producer did not state cannot be "
                + "distinguished from one that was guessed"
        )
    }
}
